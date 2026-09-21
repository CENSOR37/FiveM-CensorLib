local lib = require "src.imports._lib.shared"
local node = require "src.imports._scene.node.shared"
local instantiate = require "src.imports._scene.prefab.shared"

local scene = lib.class()
local instances = {}
local stopping = false

local function traceback(err)
    return debug.traceback(tostring(err), 2)
end

function scene:constructor()
    assert(not stopping, "cannot create a scene while the resource is stopping")
    self.destroyed = false
    self._nodes = {}
    self._roots = {}
    self._next_id = 0
    instances[self] = true
end

function scene:_assert_live_node(current)
    assert(not self.destroyed, "scene is destroyed")
    assert(type(current) == "table" and current._scene == self and self._nodes[current._id] == current,
        "node must belong to this scene")
    assert(not current.destroyed and not current._closing, "node is being destroyed")
end

function scene:create_node(name, parent)
    assert(not self.destroyed, "scene is destroyed")
    assert(type(name) == "string" and name ~= "", "node requires a non-empty name")
    if (parent ~= nil) then self:_assert_live_node(parent) end

    self._next_id = self._next_id + 1
    local current = node:new(self, self._next_id, name, parent)
    self._nodes[current._id] = current
    local siblings = parent and parent._children or self._roots
    siblings[#siblings + 1] = current
    return current
end

function scene:get_node(id)
    return self._nodes[id]
end

function scene:get_roots()
    local result = {}
    for i = 1, #self._roots do result[i] = self._roots[i] end
    return result
end

function scene:find_nodes(selector)
    assert(selector == nil or type(selector) == "string" or type(selector) == "table",
        "component selector must be a name or cslib.class")
    local result = {}
    for _, root in ipairs(self._roots) do
        if (selector == nil or root:has_component(selector)) then result[#result + 1] = root end
        for _, child in ipairs(root:find_descendants(selector)) do result[#result + 1] = child end
    end
    return result
end

function scene:instantiate(definition, parent)
    return instantiate(self, definition, parent)
end

function scene:destroy()
    if (self.destroyed) then return end
    self.destroyed = true
    instances[self] = nil

    local errors = {}
    local roots = self:get_roots()
    for i = #roots, 1, -1 do
        local ok, err = xpcall(roots[i].destroy, traceback, roots[i])
        if (not ok) then errors[#errors + 1] = err end
    end
    if (#errors > 0) then error(table.concat(errors, "\n"), 0) end
end

lib.resource.on_stop(function()
    stopping = true
    local pending, errors = {}, {}
    for instance in pairs(instances) do pending[#pending + 1] = instance end
    for _, instance in ipairs(pending) do
        local ok, err = xpcall(instance.destroy, traceback, instance)
        if (not ok) then errors[#errors + 1] = err end
    end
    if (#errors > 0) then error(table.concat(errors, "\n"), 0) end
end)

return scene
