local lib = require "src.imports._lib.shared"
local states <const> = require "src.resource.cache.client"
local spatial_grid <const> = require "src.imports._spatial-grid.shared"

local PLAYER_QUERY_SIZE <const> = vec(2.0, 2.0)
local BOUNDS <const> = { min = vec2(-10000, -10000), max = vec2(10000, 10000) }
local CELL_SIZE <const> = vec(500.0, 500.0)

local grid_system = spatial_grid:new(BOUNDS.min, BOUNDS.max, CELL_SIZE)

local handle_map = {}
local id_to_handle = {}

local active_zones = {}
local current_frame_inside = {}

local local_ped = function()
    return states.ped.value or PlayerPedId() -- might need to use PlayerPedId directly if cache becomes unreliable
end

lib.set_interval(function()
    local ped = local_ped()
    local pos = GetEntityCoords(ped)

    local results, count = grid_system:query(pos.xy, PLAYER_QUERY_SIZE)

    table.wipe(current_frame_inside)

    for i = 1, count do
        local handle = results[i]
        local data = handle_map[handle]

        if (data) then
            if (data.colshape:is_position_inside(pos)) then
                current_frame_inside[handle] = true

                if (not active_zones[handle]) then
                    active_zones[handle] = true
                    lib.emit("cslib:collision:enter", ped, data.custom_id)
                end
            end
        end
    end

    for handle in pairs(active_zones) do
        if (not current_frame_inside[handle]) then
            active_zones[handle] = nil

            local data = handle_map[handle]
            if (data) then
                lib.emit("cslib:collision:exit", ped, data.custom_id)
            end
        end
    end
end, 200)

local function insert_colshape(type, ...)
    local colshape = lib.colshape[type](...)

    assert(colshape, "^1Error: Failed to create colshape^0")
    assert(colshape.origin, "Colshape must have an origin property")
    assert(colshape.radius, "Colshape must have a radius (bounding) property")

    local next_id = lib.uuid()

    local handle = grid_system:insert(colshape.origin.xy, vec(colshape.radius * 2, colshape.radius * 2))
    handle_map[handle] = { colshape = colshape, custom_id = next_id }
    id_to_handle[next_id] = handle

    return next_id
end

local function remove_colshape(custom_id)
    local handle = id_to_handle[custom_id]
    if (not handle) then return end

    grid_system:remove(handle)

    if (active_zones[handle]) then
        active_zones[handle] = nil
        lib.emit("cslib:collision:exit", local_ped(), custom_id)
    end

    handle_map[handle] = nil
    id_to_handle[custom_id] = nil
end

-- HANLDING EXPORT
local created_exports = {}

lib.on("onResourceStop", function(resource)
    local created_by_resource = created_exports[resource]
    if not (created_by_resource) then return end

    for custom_id, _ in pairs(created_by_resource) do
        remove_colshape(custom_id)
    end

    created_exports[resource] = nil
end)

exports("collision_streamer_insert", function(type, ...)
    local invoker = GetInvokingResource()
    if not (created_exports[invoker]) then
        created_exports[invoker] = {}
    end

    local custom_id = insert_colshape(type, ...)
    created_exports[invoker][custom_id] = true

    return custom_id
end)

exports("collision_streamer_remove", function(custom_id)
    local invoker = GetInvokingResource()
    local has = created_exports?[invoker]?[custom_id]

    if (has) then
        created_exports[invoker][custom_id] = nil
        remove_colshape(custom_id)
    end
end)
