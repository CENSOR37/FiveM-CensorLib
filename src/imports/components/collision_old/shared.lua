-- ต้องสร้างโดยระบุ colshape ที่ต้องการ x
-- สามารถใส่หลายๆ colshape ได้
-- เวลา broadcast จะส่งค่า colshape id ไปด้วย
-- จะต้องเก็บค่า inside entity ที่อยู่ในแต่ละ colshape ไว้ด้วย ???
-- สร้าง class ใหม่สำหรับ colshape ที่จะเก็บใน collision ???


local native = {
    get_game_pool = GetGamePool,
    player_ped_id = PlayerPedId,
    get_entity_coords = GetEntityCoords,
}

local function get_game_objects()
    return native.get_game_pool("CObject")
end

local function get_game_peds()
    return native.get_game_pool("CPed")
end

local function get_game_vehicles()
    return native.get_game_pool("CVehicle")
end

local function table_count(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local colshape_instance = {}
colshape_instance.__index = colshape_instance
colshape_instance.__id = 0

function colshape_instance.new_id()
    colshape_instance.__id = colshape_instance.__id + 1
    return colshape_instance.__id
end

function colshape_instance.new(collision, colshape)
    local self = setmetatable({}, colshape_instance)
    self.id = colshape_instance.new_id()
    self.collision = collision
    self.colshape = colshape
    self.inside_entities = lib.set()
    self.active_entities = lib.set()

    return self
end

function colshape_instance:process_entity(entity)
    local handle = entity.handle
    local position = entity.position

    -- check conditions
    local is_inside = self.colshape:is_position_inside(position)
    local is_same_dimension = true
    if (type(self.dimension) == "number") then
        is_same_dimension = (self.dimension == (entity.dimension or self.dimension))
    end
    local is_collided = (is_inside and is_same_dimension)

    if (is_collided) then
        if not (self.inside_entities:contain(handle)) then
            self.active_entities:add(handle)
            self.inside_entities:add(handle)
            self.collision.delegates.enter:broadcast(handle)
        end

        self.active_entities:add(handle)
    end
end

function colshape_instance:after_processed()
    local inside_entities = self.inside_entities:array()
    for i = 1, #inside_entities, 1 do
        local handle = inside_entities[i]
        if not (self.active_entities:contain(handle)) then
            self.inside_entities:remove(handle)
            self.collision.delegates.exit:broadcast(handle)
        end
    end

    self.active_entities:empty()
end

function colshape_instance:destroy()
    local inside_entities = self.inside_entities:array()
    for i = 1, #inside_entities, 1 do
        local handle = inside_entities[i]
        self.collisions.delegates.exit:broadcast(handle)
    end

    self.inside_entities:empty()
    self.active_entities:empty()
end

local collision = {}
collision.__index = collision

local function internal_process_entity_info(entity)
    return {
        handle = entity,
        position = native.get_entity_coords(entity),
        dimension = 0, -- temporary
    }
end

-- this should not be accessible from outside
local function internal_collision_process(self)
    if (self.colshape.size <= 0) then return end
    local entities = {}

    for _, entity in pairs(get_game_objects()) do
        table.insert(entities, internal_process_entity_info(entity))
    end

    for _, entity in pairs(get_game_peds()) do
        table.insert(entities, internal_process_entity_info(entity))
    end

    for _, entity in pairs(get_game_vehicles()) do
        table.insert(entities, internal_process_entity_info(entity))
    end

    for _, collision_inst in pairs(self.colshape.instances) do
        for i = 1, #entities, 1 do
            local entity = entities[i]
            collision_inst:process_entity(entity)
        end

        collision_inst:after_processed()
    end
end

function collision.new(opts)
    opts = opts or {}

    local self = setmetatable({}, collision)
    self.is_debug = true
    self.is_destroyed = false
    self.colshape = {
        id = 0,
        size = 0,
        instances = {},
    }
    self.dimension = 0
    self.tickrate = opts.tickrate or 0
    self.interval = opts.interval or 300
    self.delegates = {
        enter = lib.delegate.new(),
        overlap = lib.delegate.new(),
        exit = lib.delegate.new(),
    }
    self.inside_entities = lib.set()

    if (lib.is_client and self.is_debug) then
        local debug_interval
        debug_interval = lib.on_tick(function()
            if (self.is_destroyed) then
                debug_interval:destroy()
            else
                for _, collision_inst in pairs(self.colshape.instances) do
                    collision_inst.colshape:draw_debug()
                end
            end
        end)
    end

    do
        local tick_timer
        tick_timer = lib.set_interval(function()
            if (self.is_destroyed) then
                tick_timer:destroy()
            else
                internal_collision_process(self)
            end
        end, self.interval)
    end

    return self
end

function collision:destroy()
    if (self.is_destroyed) then return end

    self.is_destroyed = true
    if (self.on_overlapping_timer) then
        self.on_overlapping_timer:destroy()
    end

    for _, delegate in pairs(self.delegates) do
        delegate:empty()
    end
end

function collision:add_colshape(colshape)
    if not colshape then return end
    self.colshape.id = self.colshape.id + 1
    self.colshape.instances[self.colshape.id] = colshape_instance.new(self, colshape)
    self.colshape.size = table_count(self.colshape.instances)
    return self.colshape.id
end

function collision:remove_colshape(id)
    if not id then return end
    self.colshape.instances[id] = nil
    self.colshape.size = table_count(self.colshape.instances)
end

function collision:on_begin_overlap(listener)
    local id = self.delegates.enter:add(listener)
    return { id = id, type = "enter" }
end

function collision:on_overlapping(listener)
    local id = self.delegates.overlap:add(listener)

    if (self.delegates.overlap:size() == 1) then
        self.on_overlapping_timer = lib.set_interval(function()
            local inside_entities = self.inside_entities:array()
            for i = 1, #inside_entities, 1 do
                local handle = inside_entities[i]
                self.delegates.overlap:broadcast(handle)
            end
        end, self.tickrate)

        self.on_begin_overlap_id = self:on_begin_overlap(function(handle)
            self.inside_entities:add(handle)
        end)

        self.on_end_overlap_id = self:on_end_overlap(function(handle)
            self.inside_entities:remove(handle)
        end)
    end

    return { id = id, type = "overlap" }
end

function collision:on_end_overlap(listener)
    local id = self.delegates.exit:add(listener)
    return { id = id, type = "exit" }
end

function collision:off(listener_info)
    if (listener_info.type == "enter") then
        self.delegates.enter:remove(listener_info.id)
    elseif (listener_info.type == "exit") then
        self.delegates.exit:remove(listener_info.id)
    elseif (listener_info.type == "overlap") then
        self.delegates.overlap:remove(listener_info.id)
        if (self.delegates.overlap:size() == 0) then
            self.delegates.enter:remove(self.on_begin_overlap_id)
        end
    end
end

lib_module = setmetatable({
    new = collision.new,
}, {
    __call = function(_, ...)
        return collision.new(...)
    end,
})
