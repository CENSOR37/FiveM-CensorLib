local native = {
    player_ped_id = PlayerPedId,
    get_entity_coords = GetEntityCoords,
}

local zone = {}
zone.__index = zone
zone.__instances = {}
zone.__id = 10
zone.__delegate = lib.delegate()
zone.__interval = -1

zone.__process = function()
    local ped = native.player_ped_id()
    local pos = native.get_entity_coords(ped)

    for _, instance in pairs(zone.__instances) do
        local is_overlapping = instance.colshape:is_position_inside(pos)

        if (is_overlapping) then
            if (not instance.is_player_overlapping) then
                instance.is_player_overlapping = true
                instance.delegates.enter:broadcast()
            end
        else
            if (instance.is_player_overlapping) then
                instance.is_player_overlapping = false
                instance.delegates.exit:broadcast()
            end
        end
    end
end

zone.__instance_created = function()
    if (zone.__interval) then return end

    zone.__interval = lib.set_interval(zone.__process, 250)
end

zone.__instance_destroyed = function()
    local count = 0
    for _, instance in pairs(zone.__instances) do
        count = count + 1
    end

    if (count <= 0) then
        zone.__interval:destroy()
        zone.__interval = nil
    end
end

function zone.new_id()
    zone.__id = zone.__id + 1
    return zone.__id
end

function zone.new(colshape)
    local self = {}
    self.id = zone.new_id()
    self.destroyed = false
    self.colshape = colshape
    self.is_player_overlapping = false
    self.periodic_handle = -1
    self.delegates = {
        enter = lib.delegate.new(),
        overlap = lib.delegate.new(),
        exit = lib.delegate.new(),
    }

    local new_zone = setmetatable(self, zone)
    zone.__instances[new_zone.id] = new_zone
    zone.__instance_created()

    return new_zone
end

function zone:destroy()
    if (self.destroyed) then return end
    self.destroyed = true

    self.delegates.exit:broadcast()
    for _, delegate in pairs(self.delegates) do
        delegate:empty()
    end

    zone.__instances[self.id] = nil
    zone.__instance_destroyed()
end

function zone:on_begin_overlap(listener)
    lib.validate.type.assert(listener, "function")

    local id = self.delegates.enter:add(listener)

    return { id = id, type = "enter" }
end

function zone:on_overlapping(listener)
    lib.validate.type.assert(listener, "function")

    local id = self.delegates.overlap:add(listener)

    if (self.delegates.overlap:size() == 1) then
        self.on_overlapping_timer = lib.set_interval(function()
            self.delegates.overlap:broadcast()
        end, 0)
    end

    return { id = id, type = "overlap" }
end

function zone:on_end_overlap(listener)
    lib.validate.type.assert(listener, "function")

    local id = self.delegates.exit:add(listener)

    return { id = id, type = "exit" }
end

function zone:off(listener_info)
    lib.validate.type.assert(listener_info, "table")
    lib.validate.type.assert(listener_info.id, "number")
    lib.validate.type.assert(listener_info.type, "string")

    local event_type = listener_info.type
    self.delegates[event_type]:remove(listener_info.id)

    if (event_type == "overlap" and self.delegates.overlap:size() <= 0) then
        self.delegates.enter:remove(self.on_begin_overlap_id)
    end
end

lib_module = setmetatable({}, {
    __index = function(t, k)
        if (k == "new") then return zone.new end

        local colshape = lib.colshape[k]
        assert(colshape, ("colshape.%s does not exist"):format(k))

        return setmetatable({
            new = function(...)
                return zone.new(colshape.new(...))
            end,
        }, {
            __call = function(t, ...)
                return t.new(...)
            end,
        })
    end,
    __call = function(_, ...)
        return zone.new(...)
    end,
})
