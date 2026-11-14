local lib = require "src.imports._lib.shared"

local lib_name = "censorlib"
local current_res_name = GetCurrentResourceName()
local exp = exports[lib_name]
local collision = lib.class()

-- TODO: implement preload colshape ? this would allow instant on_enter and on_exit events without waiting for the next streamer update
-- But would we really need it for most use cases?

function collision:constructor(colshape)
    assert(GetResourceState(lib_name) == "started", ("^1[ERROR] Resource %s must be started to use collision class^0"):format(lib_name))

    local colshape_type = nil

    if (lib.colshape.circle.is_a(colshape)) then
        colshape_type = "circle"
    elseif (lib.colshape.sphere.is_a(colshape)) then
        colshape_type = "sphere"
    elseif (lib.colshape.poly.is_a(colshape)) then
        colshape_type = "poly"
    end

    assert(colshape_type, "^1[ERROR] Invalid colshape provided to collision class^0")

    self.colshape_type = colshape_type
    self.colshape = colshape
    self.is_inside = false
    self.delegate_enter = lib.delegate()
    self.delegate_exit = lib.delegate()
    self.collision_id = nil

    self:init_streamer()

    self.event_resource_start = lib.on("onResourceStart", function(started_resource)
        if (started_resource == lib_name) then
            self:init_streamer()
        end
    end)

    self.event_resource_stop = lib.on("onResourceStop", function(stopping_resource)
        if (stopping_resource == current_res_name) then
            self:uninit_streamer()
        elseif (stopping_resource == lib_name) then
            self:uninit_streamer()
        end
    end)
end

function collision:destroy()
    lib.off(self.event_resource_start)
    lib.off(self.event_resource_stop)

    self:uninit_streamer()
end

function collision:init_streamer()
    if (self.collision_id) then
        self:uninit_streamer()
    end

    self.collision_id = exp.collision_streamer_insert(nil, self.colshape_type, table.unpack(self.colshape.args))

    self.event_enter = lib.on("cslib:collision:enter", function(in_entity, in_collision_id)
        if (self.collision_id ~= in_collision_id) then return end
        self.is_inside = true
        self.delegate_enter:broadcast(in_entity, in_collision_id)
    end)

    self.event_exit = lib.on("cslib:collision:exit", function(in_entity, in_collision_id)
        if (self.collision_id ~= in_collision_id) then return end
        self.is_inside = false
        self.delegate_exit:broadcast(in_entity, in_collision_id)
    end)
end

function collision:uninit_streamer()
    if (self.collision_id) then
        pcall(function(...)
            exp.collision_streamer_remove(nil, self.collision_id)
        end)
        self.collision_id = nil
    end

    if (self.event_enter) then
        lib.off(self.event_enter)
        self.event_enter = nil
    end

    if (self.event_exit) then
        lib.off(self.event_exit)
        self.event_exit = nil
    end

    if (self.is_inside) then
        self.delegate_exit:broadcast(nil, self.collision_id)
        self.is_inside = false
    end
end

function collision:on_enter(listener)
    self.delegate_enter:bind(listener)
end

function collision:on_exit(listener)
    self.delegate_exit:bind(listener)
end

local exp = {}
exp.new = function(_, ...) return _ == exp and collision:new(...) or collision:new(_, ...) end
exp.circle = function(...) return collision:new(lib.colshape.circle(...)) end
exp.sphere = function(...) return collision:new(lib.colshape.sphere(...)) end
exp.poly = function(...) return collision:new(lib.colshape.poly(...)) end

return setmetatable(exp, { __call = function(_, ...) return collision:new(...) end })
