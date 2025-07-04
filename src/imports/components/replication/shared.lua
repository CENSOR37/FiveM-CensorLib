--[[
    Sync Map
    is a feature used for efficient replication of dynamic maps over a network,
    designed to minimize bandwidth usage by only sending deltas (changes) to the map rather than the entire map.

    additional features to implement:
     - relevancy filtering: only send changes to clients that are relevant to them (without this feature this is no different than global statebag)

    available methods:
    - new() : creates a new synced map instance,
    - set(key, value) : sets a value for the specified key,
    - delete(key) : deletes the specified key,
    - mark_dirty() : marks the map as dirty, indicating that changes have been made and need to be replicated.

    available abstract methods:
    - post_replicate_add(added_indices, final_size)
    - post_replicate_change(changed_indices, final_size)
    - pre_replicate_remove(removed_indices, final_size)
 ]]

local table_wipe = table.wipe
local map = lib.map.class

local synced_map = {}
synced_map.__index = synced_map
synced_map.__id = 10
synced_map.__exists = lib.set()
setmetatable(synced_map, map)

local function event_name(name, action)
    lib.validate.type.assert(name, "string")
    lib.validate.type.assert(action, "string")

    return ("syncmap:%s.%s"):format(name, action)
end

local function commit_delta(self, incoming_deltas)
    if (next(incoming_deltas) == nil) then return false end

    for id, delta in pairs(incoming_deltas) do
        local action = delta[1]

        if (action == "set") then
            local value = delta[2]

            self.super:set(id, value)
        elseif (action == "delete") then
            self.super:delete(id)
        else
            error(("synced_map:mark_dirty() called with invalid action '%s'"):format(action))
        end
    end

    return true
end

function synced_map.new(name)
    lib.validate.type.assert(name, "string")
    assert(synced_map.__exists:has(name) == false, ("synced_map.new() called with existing name '%s'"):format(name))
    synced_map.__exists:add(name)

    synced_map.__id = synced_map.__id + 1

    local self = map.default()
    self.super = setmetatable({}, {
        __index = function(tbl, k)
            local super_func = rawget(map, k)

            assert(super_func and type(super_func) == "function", ("synced_map:super() called with invalid method '%s'"):format(k))

            -- this will get garbage collecte eventually, no need to cache it
            return function(_, ...)
                return super_func(self, ...)
            end
        end,
    })
    self.name = ("syncmap:%s"):format(name)
    self.id = synced_map.__id
    self.deltas = {}

    if (lib.is_server) then
        lib.resource.callback.register(event_name(self.name, "request.data"), function()
            return self.data
        end)
    else
        lib.resource.callback(event_name(self.name, "request.data")).callback(function(data)
            self:clear()

            for _, entry in pairs(data) do
                local key = entry.key
                local value = entry.value

                if (self.super:has(key)) then
                    lib.print.warn("synced_map", self.name, "key already exists skipping", key, value)
                else
                    self.super:set(key, value)
                end
            end

            -- implement the post delegate here
        end)

        lib.resource.on_server(event_name(self.name, "commit"), function(incoming_deltas)
            commit_delta(self, incoming_deltas)

            -- implement the post delegate here
        end)
    end

    return setmetatable(self, synced_map)
end

-- this function will need to manually called, which will sent the deltas to the client
function synced_map:mark_dirty()
    assert(lib.is_server, "synced_map:mark_dirty() can only be called on the server")

    if (commit_delta(self, self.deltas)) then
        lib.resource.emit_all_clients(event_name(self.name, "commit"), self.deltas)
    end

    table_wipe(self.deltas)
end

function synced_map:set(id, value)
    lib.validate.type.assert(id, "string", "number", "boolean")
    lib.validate.type.assert(value, "string", "number", "boolean", "table", "nil")

    self.deltas[id] = { "set", value }
end

function synced_map:delete(id)
    lib.validate.type.assert(id, "string", "number", "boolean")

    self.deltas[id] = { "delete" }
end

function synced_map:clear()
    self.super:clear()

    -- Clear deltas as well
    table_wipe(self.deltas)
end

local classwarp = function(class, ...)
    return setmetatable({
        new = class.new,
    }, {
        __call = function(t, ...)
            return t.new(...)
        end,
    })
end

lib_module.map = classwarp(synced_map)
