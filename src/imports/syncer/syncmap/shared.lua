--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.

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
    PRE_REPLICATED_CHANGE = "pre_replicated_change",   -- client only, before the change is applied to the local map.
    POST_REPLICATED_CHANGE = "post_replicated_change", -- client only, after the change has been applied to the local map.
}

-- Minimum interval (ms) between full-sync requests from a client. A burst of skipped
-- packets while a full sync is already in flight must not become a burst of requests.
local FULL_SYNC_REQUEST_COOLDOWN_MS <const> = 1000

function syncmap:__len()
    return #self.map
end

function syncmap:new(in_id, in_opts)
    in_opts = in_opts or {}
    local self = setmetatable({}, syncmap)
    self.opts = {}
    self.opts.only_relevant = in_opts.only_relevant == true
    self.id = in_id
    self.map = lib.map()
    self.version = 0
    self.event_handlers = {}

    self.listeners = {}
    for _, value in pairs(ENUM_SYNC_MAP_EVENT) do
        self.listeners[value] = {}
    end

    if (is_server) then
        -- Random per-instance token. Lets clients distinguish "the server instance was
        -- recreated and its version counter reset" (must resync) from "stale packet" (must drop).
        self.epoch = math.random(1, 0x7FFFFFFF)
        -- Dirty tracking (Fast Array Serializer style): we remember WHICH keys changed,
        -- and snapshot their latest state at flush time. N writes to one key => 1 delta.
        self.dirty_keys = {}
        self.pending_clear = false
        self.relevant_sources = {}
        self.full_deltas = nil
        self.full_deltas_version = -1
        self:_init_server()
    else
        self.epoch = nil
        self.awaiting_full_sync = false
        self.full_sync_requested_at = nil
        self:_init_client()
    end

    return self
end

function syncmap:destroy()
    for i = 1, #self.event_handlers do
        lib.off(self.event_handlers[i])
    end
    table_wipe(self.event_handlers)
    for _, callbacks in pairs(self.listeners) do
        table_wipe(callbacks)
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

-- BEGIN OF: SERVER

function syncmap:_build_full_deltas()
    -- Fresh table each rebuild: never mutate a table that may still be referenced by an in-flight send.
    local full_deltas, n = {}, 0

    self.map:for_each(function(key, value)
        n = n + 1
        full_deltas[n] = { ENUM_SYNC_MAP_ACTION.SET, key, value }
    end)

    self.full_deltas = full_deltas
    self.full_deltas_version = self.version
end

--- Sends every pending change as ONE delta packet and bumps the version.
--- Returns true if something was sent.
function syncmap:_flush()
    local pending_clear = self.pending_clear
    if (not pending_clear and next(self.dirty_keys) == nil) then
        return false
    end

    local deltas, n = {}, 0

    if (pending_clear) then
        n = 1
        deltas[1] = { ENUM_SYNC_MAP_ACTION.CLEAR }
    end

    for key in pairs(self.dirty_keys) do
        local value = self.map:get(key)
        if (value ~= nil) then
            n = n + 1
            deltas[n] = { ENUM_SYNC_MAP_ACTION.SET, key, value }
        elseif (not pending_clear) then
            -- After a CLEAR the client has nothing to delete; only emit DELETE otherwise.
            n = n + 1
            deltas[n] = { ENUM_SYNC_MAP_ACTION.DELETE, key }
        end
    end

    table_wipe(self.dirty_keys)
    self.pending_clear = false
    self.version += 1

    local event_name = self:_eventname("incoming_deltas")
    if (self.opts.only_relevant) then
        for src in pairs(self.relevant_sources) do
            lib.resource.emit_client_adaptive(event_name, src, self.epoch, self.version, deltas)
        end
    else
        lib.resource.emit_all_clients_adaptive(event_name, self.epoch, self.version, deltas)
    end

    return true
end

function syncmap:_send_full_sync(src)
    -- Flush first so the snapshot is version-consistent: the map content and the version
    -- number sent together describe the same state, and the cache below is never stale.
    self:_flush()

    if (self.full_deltas_version ~= self.version) then
        self:_build_full_deltas()
    end

    lib.resource.emit_client_adaptive(self:_eventname("incoming_full_sync"), src, self.epoch, self.version, self.full_deltas)
end

function syncmap:_init_server()
    self:_event(lib.resource.on_client(self:_eventname("request_full_sync"), function()
        local src = tonumber(source)
        if (not src) then return end

        if (self.opts.only_relevant and not self.relevant_sources[src]) then
            return
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

-- END OF: SERVER

-- BEGIN OF: CLIENT

function syncmap:_request_full_sync()
    local now = GetGameTimer()
    if (self.full_sync_requested_at and (now - self.full_sync_requested_at) < FULL_SYNC_REQUEST_COOLDOWN_MS) then
        return
    end

    self.full_sync_requested_at = now
    self.awaiting_full_sync = true
    lib.resource.emit_server(self:_eventname("request_full_sync"))
end

function syncmap:_apply_clear()
    local entries, n = {}, 0
    self.map:for_each(function(k, v)
        n = n + 1
        entries[n] = { k, v }
        self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, k, nil, v)
    end)

    self.map:clear()

    for i = 1, n do
        self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, entries[i][1], nil, entries[i][2])
    end
end

function syncmap:_apply_deltas(deltas)
    for i = 1, #deltas do
        local delta = deltas[i]
        local action, key, value = delta[1], delta[2], delta[3]

        if (action == ENUM_SYNC_MAP_ACTION.SET) then
            local prev_value = self.map:get(key)
            self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, key, value, prev_value)
            self.map:set(key, value)
            self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, key, value, prev_value)
        elseif (action == ENUM_SYNC_MAP_ACTION.DELETE) then
            local prev_value = self.map:get(key)
            self:_emit(ENUM_SYNC_MAP_EVENT.PRE_REPLICATED_CHANGE, key, nil, prev_value)
            self.map:delete(key)
            self:_emit(ENUM_SYNC_MAP_EVENT.POST_REPLICATED_CHANGE, key, nil, prev_value)
        elseif (action == ENUM_SYNC_MAP_ACTION.CLEAR) then
            self:_apply_clear()
        end
    end
end

function syncmap:_init_client()
    self:_event(lib.resource.on_server(self:_eventname("incoming_deltas"), function(epoch, version, deltas)
        -- No baseline yet (or the server instance changed): deltas are meaningless, we need a snapshot.
        if (self.awaiting_full_sync or epoch ~= self.epoch) then
            self:_request_full_sync()
            return
        end

        if (version <= self.version) then
            return                    -- old or duplicated
        elseif (version > self.version + 1) then
            self:_request_full_sync() -- gap detected
            return
        end

        self:_apply_deltas(deltas)
        self.version = version
    end))

    self:_event(lib.resource.on_server(self:_eventname("incoming_full_sync"), function(epoch, version, full_deltas)
        local epoch_changed = epoch ~= self.epoch
        if (not epoch_changed and version < self.version) then
            return
        end

        self.epoch = epoch
        self.awaiting_full_sync = false

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

    self:_request_full_sync()
end

-- END OF: CLIENT

-- BEGIN OF: PUBLIC API

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
    assert(key ~= nil, "syncmap:set key cannot be nil")

    if (value == nil) then
        self.map:delete(key) -- set(key, nil) is a delete, same as a plain Lua table.
    else
        self.map:set(key, value)
    end

    self.dirty_keys[key] = true
end

function syncmap:delete(key)
    assert(is_server, "syncmap:delete can only be called on the server")
    assert(key ~= nil, "syncmap:delete key cannot be nil")

    self.map:delete(key)

    self.dirty_keys[key] = true
end

function syncmap:clear()
    assert(is_server, "syncmap:clear can only be called on the server")

    self.map:clear()

    -- Everything dirtied before the clear is now irrelevant: one CLEAR supersedes it all.
    table_wipe(self.dirty_keys)
    self.pending_clear = true
end

function syncmap:mark_dirty()
    assert(is_server, "syncmap:mark_dirty can only be called on the server")
    self:_flush()
end

function syncmap:_is_player_relevant(in_src)
    local src = tonumber(in_src)
    return self.relevant_sources[src] == true, src
end

function syncmap:is_player_relevant(in_src)
    local is_relevant = self:_is_player_relevant(in_src)
    return is_relevant
end

function syncmap:add_relevant_player(in_src)
    assert(is_server, "syncmap:add_relevant_player can only be called on the server")
    if (not self.opts.only_relevant) then return end

    local is_relevant, src = self:_is_player_relevant(in_src)
    if (is_relevant or not src) then return end

    -- Flush BEFORE registering the player: pending deltas go to the existing audience only,
    -- the newcomer gets a clean snapshot (no delta + full sync for the same change).
    self:_flush()
    self.relevant_sources[src] = true
    self:_send_full_sync(src)
end

function syncmap:remove_relevant_player(in_src)
    assert(is_server, "syncmap:remove_relevant_player can only be called on the server")
    if (not self.opts.only_relevant) then return end

    local is_relevant, src = self:_is_player_relevant(in_src)
    if (not is_relevant) then return end

    self.relevant_sources[src] = nil
    -- An empty snapshot at the current version wipes the client's copy (and fires change events for every key).
    lib.resource.emit_client_adaptive(self:_eventname("incoming_full_sync"), src, self.epoch, self.version, {})
end

-- END OF: PUBLIC API

return syncmap
