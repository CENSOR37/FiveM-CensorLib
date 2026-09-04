--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.

local table_pack = table.pack
local table_unpack = table.unpack
local CreateThreadNow = Citizen.CreateThreadNow

local syncmap = require "src.imports.syncer.syncmap.shared"
local lib = require "src.imports._lib.shared"

local is_server = IsDuplicityVersion()
local is_client = not is_server

local syncnode = lib.class()

function syncnode:constructor()

end

function syncnode:is_player_relevant(in_src)
    local node_syncmap = self.__node_syncmap
    assert(in_src, "syncnode:is_player_relevant requires in_src to be set")

    return node_syncmap:is_player_relevant(in_src)
end

function syncnode:add_relevant_player(in_src)
    local node_syncmap = self.__node_syncmap
    assert(in_src, "syncnode:add_relevant_player requires in_src to be set")

    return node_syncmap:add_relevant_player(in_src)
end

function syncnode:remove_relevant_player(in_src)
    local node_syncmap = self.__node_syncmap
    assert(in_src, "syncnode:remove_relevant_player requires in_src to be set")

    return node_syncmap:remove_relevant_player(in_src)
end

local function create_syncnode_class(classname, node_opts)
    local only_relevant = lib.coalesce(node_opts?.only_relevant, false)
    local node_syncmap = syncmap:new(("syncnode:%s"):format(classname), { only_relevant = only_relevant })
    local out_class = lib.class.extends(syncnode)
    local id_to_inst = lib.map()
    local inst_to_id = lib.map()

    out_class.__node_syncmap = node_syncmap
    local id = 10

    local function next_id()
        id += 1
        return id
    end

    local function run_destructor(inst)
        if (inst.destructor) then
            CreateThreadNow(function()
                inst:destructor()
            end)
        end
    end

    local function track(inst, sync_id)
        id_to_inst:set(sync_id, inst)
        inst_to_id:set(inst, sync_id)
    end

    local function untrack(inst)
        local node_id = inst_to_id:get(inst)
        if (node_id) then
            id_to_inst:delete(node_id)
            inst_to_id:delete(inst)
        end
        return node_id
    end

    local _node_new = out_class.new

    function out_class:new(...)
        assert(is_server, "syncnode instances must be created on the server")

        local out_inst = _node_new(self, ...)
        next_id()
        node_syncmap:set(id, table_pack(...))
        node_syncmap:mark_dirty()
        track(out_inst, id)

        return out_inst
    end

    function out_class:destroy()
        assert(is_server, "syncnode:destroy can only be called on the server")

        run_destructor(self)

        local node_id = untrack(self)
        if (node_id) then
            node_syncmap:delete(node_id)
            node_syncmap:mark_dirty()
        end
    end

    if (is_client) then
        node_syncmap:on("post_replicated_change", function(key, value, prev_value)
            local instance = id_to_inst:get(key)
            local is_deleting = (instance ~= nil and value == nil)
            local is_creating = (instance == nil and value ~= nil)

            if (is_deleting) then
                untrack(instance)
                run_destructor(instance)
            end

            if (is_creating) then
                local inst = _node_new(out_class, table_unpack(value, 1, value.n))
                track(inst, key)
            end
        end)
    end

    lib.resource.on_stop(function()
        local snapshot = {}
        local snapshot_len = 0
        id_to_inst:for_each(function(key, object)
            snapshot_len += 1
            snapshot[snapshot_len] = object
        end)

        for i = 1, snapshot_len, 1 do
            local instance = snapshot[i]
            if (is_server) then
                instance:destroy()
            else
                untrack(instance)
                run_destructor(instance)
            end
        end
    end)

    return out_class
end

return setmetatable({ new = create_syncnode_class }, {
    __call = function(t, ...)
        return create_syncnode_class(...)
    end,
})
