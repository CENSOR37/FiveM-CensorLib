local lib = require "src.imports._lib.shared"
local states <const> = require "src.resource.cache.client"

local GTA_SYNC_ENTITY_TYPES <const> = {
    AUTOMOBILE = 0,
    BIKE = 1,
    BOAT = 2,
    DOOR = 3,
    HELI = 4,
    OBJECT = 5,
    PED = 6,
    PICKUP = 7,
    PICKUP_PLACEMENT = 8,
    PLANE = 9,
    SUBMARINE = 10,
    PLAYER = 11,
    TRAILER = 12,
    TRAIN = 13,
}

local id_to_handle = {}
local handle_to_id = {}
local inside_zone = {}

local local_ped = function()
    return states.ped.value or PlayerPedId() -- might need to use PlayerPedId directly if cache becomes unreliable
end

local function set_colshape_only_player(handle)
    for key, value in pairs(GTA_SYNC_ENTITY_TYPES) do
        SetColshapeEntityType(handle, value, false)
    end
    SetColshapeEntityType(handle, GTA_SYNC_ENTITY_TYPES.PLAYER, true)
end

AddEventHandler("onColshapeEnter", function(entity, handle)
    local ped = local_ped()
    if (entity ~= ped) then return end

    inside_zone[handle] = true
    lib.emit("cslib:collision:enter", ped, handle_to_id[handle])
end)

AddEventHandler("onColshapeExit", function(entity, handle)
    local ped = local_ped()
    if (entity ~= ped) then return end

    if (inside_zone[handle]) then
        inside_zone[handle] = nil
        lib.emit("cslib:collision:exit", ped, handle_to_id[handle])
    end
end)

local function insert_colshape(type, ...)
    local colshape = lib.colshape[type](...)

    assert(colshape, "^1Error: Failed to create colshape^0")
    assert(colshape.origin, "Colshape must have an origin property")
    assert(colshape.radius, "Colshape must have a radius (bounding) property")

    local next_id = lib.uuid()

    local handle = nil
    if (colshape.shapetype == "sphere") then
        handle = CreateColshapeSphere(colshape:native_args())
    elseif (colshape.shapetype == "poly") then
        handle = CreateColshapePolygon(colshape:native_args())
    elseif (colshape.shapetype == "circle") then
        handle = CreateColshapeCircle(colshape:native_args())
    end

    assert(handle, "^1Error: Failed to create native colshape^0")

    set_colshape_only_player(handle)

    id_to_handle[next_id] = handle
    handle_to_id[handle] = next_id

    return next_id
end

local function remove_colshape(custom_id)
    local handle = id_to_handle[custom_id]
    if (handle) then
        DeleteColshape(handle)

        if (inside_zone[handle]) then
            inside_zone[handle] = nil
            lib.emit("cslib:collision:exit", local_ped(), custom_id)
        end

        id_to_handle[custom_id] = nil
        handle_to_id[handle] = nil
    end
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
