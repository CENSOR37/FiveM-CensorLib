local native = {
    create_thread_now = Citizen.CreateThreadNow,
    citizen_await = Citizen.Await,
    create_vehicle_server_setter = CreateVehicleServerSetter,
    create_vehicle = CreateVehicle,
    create_ped = CreatePed,
    create_object_no_offset = CreateObjectNoOffset,
    set_entity_coords = SetEntityCoords,
    set_entity_rotation = SetEntityRotation,
    does_entity_exist = DoesEntityExist,
    delete_entity = DeleteEntity,
}

local entity_types = {
    vehicle = 1,
    ped = 2,
    object = 3,
}

local create_vehicle = function(model, position, rotation, is_networked)
    local entity

    if (lib.is_server) then
        entity = native.create_vehicle_server_setter(model, "automobile", position.x, position.y, position.z, 0.0)
    else
        entity = native.create_vehicle(model, position.x, position.y, position.z, 0.0, is_networked, false)
    end

    return entity
end

local entity = {}
entity.__index = entity
entity.__instances = {}

lib.resource.on_stop(function()
    for key, value in pairs(entity.__instances) do
        value:destroy()
    end
end)

function entity.new(model, position, rotation, entity_type, is_network)
    lib.validate.type.assert(model, "string", "number")
    lib.validate.type.assert(position, "vector3", "vector4", "table")
    lib.validate.type.assert(rotation, "vector3", "vector4", "table")
    lib.validate.type.assert(is_network, "boolean", "nil")

    if (lib.is_server) then
        is_network = true
    end

    local self = setmetatable({}, entity)
    self.model = type(model) == "number" and model or joaat(model)
    self.is_networked = is_network and true or false
    self.handle = -1
    self.destroyed = false
    self.delegate_on_created = lib.delegate()
    self.delegate_on_destroyed = lib.delegate()

    -- init
    native.create_thread_now(function()
        if not (lib.is_server) then
            lib.streaming.model.request(self.model).await()
        end

        if (self.destroyed) then return end

        if (entity_type == entity_types.vehicle) then
            self.handle = create_vehicle(self.model, position, rotation, self.is_networked)
        elseif (entity_type == entity_types.ped) then
            self.handle = native.create_ped(4, self.model, position.x, position.y, position.z, rotation.z, self.is_networked, false)
        elseif (entity_type == entity_types.object) then
            self.handle = native.create_object_no_offset(self.model, position.x, position.y, position.z, self.is_networked, false, false)
        end
        entity.__instances[self.handle] = self

        native.set_entity_coords(self.handle, position.x, position.y, position.z, false, false, false, false)
        native.set_entity_rotation(self.handle, rotation.x, rotation.y, rotation.z, 0, false)

        self.delegate_on_created:broadcast()
    end)

    return self
end

function entity:on_created(callback)
    lib.validate.type.assert(callback, "function")

    if (self:is_valid()) then
        callback()
    end

    local delegate_handle
    delegate_handle = self.delegate_on_created:add(function()
        callback()
        self.delegate_on_created:remove(delegate_handle)
    end)
end

function entity:on_destroyed(callback)
    lib.validate.type.assert(callback, "function")

    if (self.destroyed) then
        callback()
    end

    local delegate_handle
    delegate_handle = self.delegate_on_destroyed:add(function()
        callback()
        self.delegate_on_destroyed:remove(delegate_handle)
    end)
end

function entity:wait_for_creation()
    local p = promise.new()
    self:on_created(function()
        p:resolve(true)
    end)

    return native.citizen_await(p)
end

function entity:is_valid()
    return native.does_entity_exist(self.handle)
end

function entity:destroy()
    self.destroyed = true
    self.delegate_on_destroyed:broadcast()

    if (self:is_valid()) then
        native.delete_entity(self.handle)
    end
end

-- @ class object
local object_class = {}
object_class.__index = object_class
setmetatable(object_class, { __index = entity })

function object_class.new(model, position, rotation)
    local self = setmetatable(entity.new(model, position, rotation, entity_types.object), object_class)
    self:wait_for_creation()

    return self
end

-- @ class ped
local ped_class = {}
ped_class.__index = ped_class
setmetatable(ped_class, { __index = entity })

function ped_class.new(model, position, rotation)
    local self = setmetatable(entity.new(model, position, rotation, entity_types.ped), ped_class)
    self:wait_for_creation()

    return self
end

-- @ class vehicle
local vehicle_class = {}
vehicle_class.__index = vehicle_class
setmetatable(vehicle_class, { __index = entity })

function vehicle_class.new(model, position, rotation)
    local self = setmetatable(entity.new(model, position, rotation, entity_types.vehicle), vehicle_class)
    self:wait_for_creation()

    return self
end

local classwarp = function(class, ...)
    return setmetatable({
        new = class.new,
    }, {
        __call = function(t, ...)
            return lib.async(t.new)(...)
        end,
    })
end

lib_module.ped = classwarp(ped_class)
lib_module.object = classwarp(object_class)
lib_module.vehicle = classwarp(vehicle_class)
