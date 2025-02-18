local collision_manager = {}
collision_manager.__index = collision_manager
local current_id = 10

function newid()
    current_id = current_id + 1
    return current_id
end

function collision_manager.new()
    local self = setmetatable({}, collision_manager)
    self.collisions = lib.set()

    return self
end

function collision_manager:register(colshape)
    lib.validate.type.assert(colshape, "table")

    local instance = {
        id = newid(),
        colshape = colshape,
        inside_entities = lib.set(),
    }

    self.collisions:add(instance)

    return instance
end

function collision_manager:unregister(colshape)
    lib.validate.type.assert(colshape, "table")
    self.collisions:remove(colshape)
end

function collision_manager:update()
    for i = 1, #self.collisions do
        local instance = self.collisions[i]
        local colshape = instance.colshape

        local entities = colshape:get_entities_inside()
        local previous_entities = instance.inside_entities
    end
end

-- local collision = {}
-- collision.__index = collision
-- collision.__instances = {}

-- local on_tick_delegate = lib.delegate()


-- cslib.set_interval(function()
--     local index_to_remove = {}

--     for i = 1, #collision.__instances do
--         local instance = collision.__instances[i]
--         if (instance.destroyed) then
--             index_to_remove[#index_to_remove + 1] = i
--         end
--     end

--     for i = 1, #index_to_remove do
--         table.remove(collision.__instances, index_to_remove[i])
--     end

--     -- process all instances
-- end, lib.is_server and 600 or 300)

-- function collision.new(colshape, opts)
--     opts = opts or {}

--     lib.validate.type.assert(colshape, "table")
--     lib.validate.type.assert(opts, "table")

--     local self = setmetatable({}, collision)
--     self.opts = {
--         debug = lib.coalesce(opts.debug, false),
--     }
--     self.destroyed = false
--     self.colshape = colshape
--     self.inside_entities = lib.set()

--     if (lib.is_client and self.is_debug) then
--         local debug_interval
--         debug_interval = lib.on_tick(function()
--             if (self.destroyed) then
--                 debug_interval:destroy()
--             else
--                 self.colshape:draw_debug()
--             end
--         end)
--     end

--     collision.__instances[#collision.__instances + 1] = self

--     return self
-- end

-- function collision:destroy()
--     if (self.destroyed) then return end

--     self.destroyed = true
-- end

-- lib_module = setmetatable({
--     new = collision.new,
--     events = {},
-- }, {
--     __call = function(_, ...)
--         return collision.new(...)
--     end,
-- })
