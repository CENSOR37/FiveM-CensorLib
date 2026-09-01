local lib = require "src.imports._lib.shared"
local table_wipe = table.wipe
local is_server = lib.is_server

--[[ Sync Map Module ]]
local syncmap <const> = {}
syncmap.__index = syncmap

local ENUM_SYNC_MAP_ACTION <const> = {
    SET = 1,
    DELETE = 2,
    CLEAR = 3,
}

local ENUM_SYNC_MAP_EVENT <const> = {
    PRE_REPLICATED_CHANGE = "pre_replicated_change",   -- only being invoke only on the client.
    POST_REPLICATED_CHANGE = "post_replicated_change", -- only being invoke only on the client, after the change has been applied to the local map.
}

function syncmap:__len()
    return #self.map
end

function syncmap:new(in_id, in_opts)
    in_opts = in_opts or {}
    local self = setmetatable({}, syncmap)
    self.opts = {}
    self.opts.only_relevant = in_opts.only_relevant == true
    self.id = in_id
    self.deltas = {}
    self.full_deltas = {}
    self.full_deltas_version = -1
    self.relevant_sources = {}
    self.event_handlers = {}
    self.map = lib.map()
    self.version = 0

    self.listeners = {}
    for key, value in pairs(ENUM_SYNC_MAP_EVENT) do
        self.listeners[value] = {}
    end

    if (is_server) then
        self:_init_server()
    else
        self:_init_client()
    end

    return self
end

function syncmap:destroy()
    for i = 1, #self.event_handlers do
        lib.off(self.event_handlers[i])
    end
end

-- BEGIN OF: INTERNAL EVENT SYSTEM (for pre/post replicated change events)

function syncmap:on(event_name, callback)
    assert(self.listeners[event_name], ("Invalid event name: %s"):format(event_name))
    table.insert(self.listeners[event_name], callback)
end

function syncmap:_emit(event_name, ...)
    local callbacks = self.listeners[event_name]
    for i = 1, #callbacks do
        local success, err = pcall(callbacks[i], ...)
        if (not success) then
            print(("^1[SyncMap Error] Event '%s' callback failed: %s^0"):format(event_name, err))
        end
    end
end

-- END OF: INTERNAL EVENT SYSTEM

function syncmap:_eventname(in_name)
    return ("syncmap:%s:%s"):format(self.id, in_name)
end

function syncmap:_event(event)
    self.event_handlers[#self.event_handlers + 1] = event
    return event
end

function syncmap:_append_delta(action, key, value)
    self.deltas[#self.deltas + 1] = { action, key, value }
end

function syncmap:_build_full_deltas()
    table_wipe(self.full_deltas)

    self.map:for_each(function(key, value)
        self.full_deltas[#self.full_deltas + 1] = { ENUM_SYNC_MAP_ACTION.SET, key, value }
    end)

    self.full_deltas_version = self.version
end

function syncmap:_send_full_sync(src)
    if (self.full_deltas_version ~= self.version) then
        self:_build_full_deltas()
    end

    lib.resource.emit_client_adaptive(self:_eventname("incoming_full_sync"), src, self.version, self.full_deltas)
end

function syncmap:_send_deltas(deltas, src)
    lib.resource.emit_client_adaptive(self:_eventname("incoming_deltas"), src, self.version, deltas)
end

function syncmap:_send_deltas_all(deltas)
    lib.resource.emit_all_clients_adaptive(self:_eventname("incoming_deltas"), self.version, deltas)
end

function syncmap:_init_client()
    self:_event(lib.resource.on_server(self:_eventname("incoming_deltas"), function(version, deltas)
        local packet_old_or_duplicated = version <= self.version
        local packet_skipped = version > self.version + 1

        if (packet_old_or_duplicated) then
            return
        elseif (packet_skipped) then
            lib.resource.emit_server(self:_eventname("request_full_sync"))
            return
        end

        for i = 1, #deltas do
            local delta = deltas[i]
            local action, key, value = delta[1], delta[2], delta[3]
            local prev_value = self.map:get(key)

            if (action ~= ENUM_SYNC_MAP_ACTION.CLEAR) then
                self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, key, value, prev_value)
            end

            if (action == ENUM_SYNC_MAP_ACTION.SET) then
                self.map:set(key, value)
                self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, key, value, prev_value)
            elseif (action == ENUM_SYNC_MAP_ACTION.DELETE) then
                self.map:delete(key)
                self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, key, nil, prev_value)
            elseif (action == ENUM_SYNC_MAP_ACTION.CLEAR) then
                local keys = {}
                self.map:for_each(function(k, v)
                    keys[#keys + 1] = { k, v }
                    self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, k, nil, v)
                end)

                self.map:clear()

                for j = 1, #keys do
                    local k, v = keys[j][1], keys[j][2]
                    self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, k, nil, v)
                end
            end
        end

        self.version = version
    end))

    self:_event(lib.resource.on_server(self:_eventname("incoming_full_sync"), function(version, full_deltas)
        local packet_old_or_duplicated = version < self.version
        if (packet_old_or_duplicated) then
            return
        end

        local previous_data = {}
        self.map:for_each(function(key, value)
            previous_data[key] = value
        end)

        self.map:clear()

        local updated_keys = {}

        for i = 1, #full_deltas do
            local delta = full_deltas[i]
            local key, value = delta[2], delta[3]

            updated_keys[key] = true

            self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, key, value, previous_data[key])
            self.map:set(key, value)
            self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, key, value, previous_data[key])
        end

        for key, old_value in pairs(previous_data) do
            if (not updated_keys[key]) then
                self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, key, nil, old_value)
                self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, key, nil, old_value)
            end
        end

        self.version = version
    end))

    lib.resource.emit_server(self:_eventname("request_full_sync"))
end

function syncmap:_init_server()
    self:_event(lib.resource.on_client(self:_eventname("request_full_sync"), function()
        local src = tonumber(source)

        if (self.opts.only_relevant) then
            if (not self.relevant_sources[src]) then
                return
            end
        end

        self:_send_full_sync(src)
    end))

    self:_event(lib.on("playerDropped", function()
        local src = tonumber(source)
        if (src) then
            self.relevant_sources[src] = nil
        end
    end))
end

function syncmap:for_each(callback)
    self.map:for_each(callback)
end

function syncmap:get(key)
    return self.map:get(key)
end

function syncmap:has(key)
    return self.map:has(key)
end

function syncmap:set(key, value)
    assert(is_server, "syncmap:set can only be called on the server")

    self.map:set(key, value)

    self:_append_delta(ENUM_SYNC_MAP_ACTION.SET, key, value)
end

function syncmap:delete(key)
    assert(is_server, "syncmap:delete can only be called on the server")

    self.map:delete(key)

    self:_append_delta(ENUM_SYNC_MAP_ACTION.DELETE, key)
end

function syncmap:clear()
    assert(is_server, "syncmap:clear can only be called on the server")

    self.map:clear()

    self:_append_delta(ENUM_SYNC_MAP_ACTION.CLEAR, nil, nil)
end

function syncmap:mark_dirty()
    assert(is_server, "syncmap:mark_dirty can only be called on the server")

    if (#self.deltas == 0) then return end

    self.version += 1

    if (self.opts.only_relevant) then
        for source, _ in pairs(self.relevant_sources) do
            self:_send_deltas(self.deltas, source)
        end
    else
        self:_send_deltas_all(self.deltas)
    end

    table_wipe(self.deltas)
end

function syncmap:_is_player_relevant(in_src)
    local src = tonumber(in_src)
    local is_relevant = self.relevant_sources[src]
    return is_relevant, src
end

function syncmap:is_player_relevant(in_src)
    local is_relevant = self:_is_player_relevant(in_src)
    return is_relevant
end

function syncmap:add_relevant_player(in_src)
    assert(is_server, "syncmap:add_relevant_player can only be called on the server")
    if (not self.opts.only_relevant) then return end

    local is_relevant, src = self:_is_player_relevant(in_src)
    if (is_relevant) then return end

    self.relevant_sources[src] = true
    self:_send_full_sync(src)
end

function syncmap:remove_relevant_player(in_src)
    assert(is_server, "syncmap:remove_relevant_player can only be called on the server")
    if (not self.opts.only_relevant) then return end

    local is_relevant, src = self:_is_player_relevant(in_src)
    if (not is_relevant) then return end

    self.relevant_sources[src] = nil
    lib.resource.emit_client_adaptive(self:_eventname("incoming_full_sync"), src, self.version, {})
end

return syncmap
