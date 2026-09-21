local spatial_grid = require "src.imports._spatial-grid.shared"

local BOUNDS <const> = { MIN = vec2(-10000, -10000), MAX = vec2(10000, 10000) }
local CELL_SIZE <const> = vec(500.0, 500.0)

-- localize
local pairs = pairs
local tonumber = tonumber
local vec = vec
local table_wipe = table.wipe
local string_format = string.format
local GetPlayerPed = GetPlayerPed
local GetEntityCoords = GetEntityCoords
local GetPlayerRoutingBucket = GetPlayerRoutingBucket
local GetPlayers = GetPlayers
local DoesEntityExist = DoesEntityExist
local Wait = Wait

local streamer = cslib.class()
local current_id = 10

local function grid_shared_handle(bucket, grid_handle)
    return (bucket << 32) | (grid_handle & 0xFFFFFFFF)
end

local function next_id()
    current_id += 1
    return current_id
end

function streamer:constructor()
    self.cell_size = vec(160, 160)

    self.cfg_move_threshold = 50.0

    self.grids = {}
    self.entity_storage = {
        position = {},
        radius = {},
        bucket = {},
        shared_grid_handle = {},
        local_grid_handle = {},
    }
    self.handle_to_entity = {}

    self.players = {}
    self.player_storage = {
        ped = {},
        last_position = {},
        bucket = {},
        streamed = {},
    }

    self.entity_dirty = false

    self:initialize()

    return self
end

function streamer:_add_player(src)
    src = tonumber(src)
    if (src and src > 0) then
        local ped = GetPlayerPed(src)
        local pos = DoesEntityExist(ped) and GetEntityCoords(ped) or vec(0, 0, 0)
        local bucket = GetPlayerRoutingBucket(src)

        self.players[src] = true
        self.player_storage.bucket[src] = bucket
        self.player_storage.last_position[src] = pos
        self.player_storage.streamed[src] = {}
        self.player_storage.ped[src] = ped

        self:_process_player_streaming(src)
    end
end

function streamer:_remove_player(src)
    src = tonumber(src)
    if (src and src > 0) then
        for entity_id in pairs(self.player_storage.streamed[src]) do
            TriggerEvent("nano_streamer:stream.out", src, entity_id)
        end

        local out_batch = {}
        for entity_id in pairs(self.player_storage.streamed[src]) do
            out_batch[#out_batch + 1] = entity_id
        end
        if (#out_batch > 0) then
            TriggerEvent("nano_streamer:stream.out.batch", src, out_batch)
        end

        self.players[src] = nil
        self.player_storage.bucket[src] = nil
        self.player_storage.last_position[src] = nil
        self.player_storage.streamed[src] = nil
        self.player_storage.ped[src] = nil
    end
end

function streamer:initialize()
    for key, src in pairs(GetPlayers()) do
        self:_add_player(src)
    end

    AddEventHandler("playerJoining", function()
        local src = source
        self:_add_player(src)
    end)

    AddEventHandler("playerDropped", function()
        local player_id = source
        self:_remove_player(player_id)
    end)

    AddEventHandler("onPlayerBucketChange", function(src, in_new_bucket, in_old_bucket)
        src = tonumber(src)
        if (src) then
            cslib.print.debug(("Player %d changed bucket from %d to %d"):format(src, in_old_bucket, in_new_bucket))
            self:_process_player_streaming(src, nil, in_new_bucket)
            self.player_storage.bucket[src] = in_new_bucket
        end
    end)

    CreateThread(function(_)
        local BATCH_SIZE = 50
        local count = 0

        while true do
            count = 0

            for src, _ in pairs(self.players) do
                count += 1

                local ped = GetPlayerPed(src)

                if (ped and ped ~= 0) then
                    local pos = GetEntityCoords(ped)
                    local last_pos = self.player_storage.last_position[src]
                    if (self.entity_dirty or not last_pos or #(pos - last_pos) > self.cfg_move_threshold) then
                        cslib.print.debug(("Player %d moved more than the threshold, updating streaming."):format(src))
                        self.player_storage.ped[src] = ped
                        self.player_storage.last_position[src] = pos
                        self:_process_player_streaming(src, pos, nil)
                    end
                end

                if (count % BATCH_SIZE == 0) then
                    Wait(0)
                end
            end

            self.entity_dirty = false

            Wait(800)
        end
    end)
end

function streamer:_get_grid(bucket)
    local grid = self.grids[bucket]
    if (not grid) then
        grid = spatial_grid:new(BOUNDS.MIN, BOUNDS.MAX, CELL_SIZE)
        self.grids[bucket] = grid
    end
    return grid
end

function streamer:_insert(entity_id, position, radius, bucket)
    position = vec(position.x, position.y, position.z)
    radius = radius or 1
    bucket = bucket or 0

    local grid = self:_get_grid(bucket)
    local grid_handle = grid:insert(position.xy, vec(radius, radius))

    local shared_handle = grid_shared_handle(bucket, grid_handle)

    local entity_storage = self.entity_storage

    entity_storage.position[entity_id] = position
    entity_storage.radius[entity_id] = radius
    entity_storage.bucket[entity_id] = bucket
    entity_storage.shared_grid_handle[entity_id] = shared_handle
    entity_storage.local_grid_handle[entity_id] = grid_handle
    self.handle_to_entity[shared_handle] = entity_id

    self.entity_dirty = true
end

function streamer:_remove(entity_id)
    local entity_storage = self.entity_storage
    local grid_shared_handle = entity_storage.shared_grid_handle[entity_id]
    if not (grid_shared_handle) then return end

    local bucket = entity_storage.bucket[entity_id]
    local grid_local_handle = entity_storage.local_grid_handle[entity_id]

    local grid = self.grids[bucket]
    if (grid) then
        grid:remove(grid_local_handle)
    end

    self.handle_to_entity[grid_shared_handle] = nil
    entity_storage.position[entity_id] = nil
    entity_storage.radius[entity_id] = nil
    entity_storage.bucket[entity_id] = nil
    entity_storage.shared_grid_handle[entity_id] = nil
    entity_storage.local_grid_handle[entity_id] = nil

    self.entity_dirty = true
end

function streamer:insert_entity(position, radius, bucket)
    local entity_id = next_id()
    self:_insert(entity_id, position, radius, bucket)
    return entity_id
end

function streamer:remove_entity(entity_id)
    self:_remove(entity_id)

    local out_batch = { entity_id }
    for player_id, streamed in pairs(self.player_storage.streamed) do
        if (streamed[entity_id]) then
            streamed[entity_id] = nil
            cslib.emit("streamer:stream.out.batch", player_id, out_batch) -- Reuse
        end
    end
end

function streamer:update_entity(entity_id, position, radius)
    local entity_storage = self.entity_storage
    local grid_shared_handle = entity_storage.shared_grid_handle[entity_id]
    if not (grid_shared_handle) then return end

    if (position) then
        entity_storage.position[entity_id] = position
    end

    if (radius) then
        entity_storage.radius[entity_id] = radius
    end

    local bucket = entity_storage.bucket[entity_id]
    local grid = self.grids[bucket]
    if (grid) then
        local grid_local_handle = entity_storage.local_grid_handle[entity_id]
        grid:update(grid_local_handle, entity_storage.position[entity_id].xy, vec(entity_storage.radius[entity_id], entity_storage.radius[entity_id]))
    end
end

function streamer:change_entity_bucket(entity_id, new_bucket)
    local entity_storage = self.entity_storage
    local position = entity_storage.position[entity_id]
    if (not position) then return end

    local radius = entity_storage.radius[entity_id]
    self:remove_entity(entity_id)
    self:_insert(entity_id, position, radius, new_bucket)
end

local stream_radius = vec(1, 1)
local scratch_buffer = {}
local scratch_candidates = {}
local scratch_stream_ins = {}
local scratch_stream_outs = {}

function streamer:_process_player_streaming(src, new_position, new_bucket)
    if (not src or src <= 0) then return end

    local pos = new_position or self.player_storage.last_position[src]
    local bucket = new_bucket or self.player_storage.bucket[src]

    local grid = self:_get_grid(bucket)
    if (grid) then
        local buffer, count = grid:query(pos.xy, stream_radius, scratch_buffer)

        for i = 1, count do
            local shared_handle = grid_shared_handle(bucket, buffer[i])
            local entity_id = self.handle_to_entity[shared_handle]
            if (entity_id) then
                scratch_candidates[entity_id] = true
            end
        end

        local current = self.player_storage.streamed[src]

        local outs_count = 0
        for entity_id in pairs(current) do
            if (not scratch_candidates[entity_id]) then
                current[entity_id] = nil
                outs_count = outs_count + 1
                scratch_stream_outs[entity_id] = true

                cslib.emit(("cslib:collision:exit"), self.player_storage.ped[src], entity_id)
            end
        end

        local ins_count = 0
        for entity_id in pairs(scratch_candidates) do
            if (not current[entity_id]) then
                current[entity_id] = true
                ins_count = ins_count + 1
                scratch_stream_ins[entity_id] = true

                cslib.emit(("cslib:collision:enter"), self.player_storage.ped[src], entity_id)
            end
        end

        if (outs_count > 0) then
            cslib.emit("nano_streamer:stream.out.batch", src, scratch_stream_outs) -- compatibility (considered deprecated)
        end

        if (ins_count > 0) then
            cslib.emit("nano_streamer:stream.in.batch", src, scratch_stream_ins)
        end

        table_wipe(scratch_buffer)
        table_wipe(scratch_candidates)
        table_wipe(scratch_stream_ins)
        table_wipe(scratch_stream_outs)
    end
end

local singleton = streamer:new()

-- HANLDING EXPORT
local created_exports = {}

cslib.on("onResourceStop", function(resource)
    local created_by_resource = created_exports[resource]
    if not (created_by_resource) then return end

    for custom_id, _ in pairs(created_by_resource) do
        singleton:remove_entity(custom_id)
    end

    created_exports[resource] = nil
end)

exports("collision_streamer_insert", function(position, raidus, bucket)
    local invoker = GetInvokingResource()
    if not (created_exports[invoker]) then
        created_exports[invoker] = {}
    end

    local custom_id = singleton:insert_entity(position, raidus, bucket)
    created_exports[invoker][custom_id] = true

    return custom_id
end)

exports("collision_streamer_remove", function(custom_id)
    local invoker = GetInvokingResource()
    local has = created_exports?[invoker]?[custom_id]

    if (has) then
        created_exports[invoker][custom_id] = nil
        singleton:remove_entity(custom_id)
    end
end)


return singleton
