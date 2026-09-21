local lib = require "src.imports._lib.shared"

local node = lib.class()

local function traceback(err)
    return debug.traceback(tostring(err), 2)
end

local function copy_array(source)
    local result = {}
    for i = 1, #source do result[i] = source[i] end
    return result
end

local function unlink(self)
    local siblings = self._parent and self._parent._children or self._scene._roots
    for i = #siblings, 1, -1 do
        if (siblings[i] == self) then
            table.remove(siblings, i)
            break
        end
    end
end

-- Internal constructor; create nodes through scene:create_node().
function node:constructor(scene, id, name, parent)
    self._scene = scene
    self._id = id
    self._name = name
    self._parent = parent
    self._children = {}
    self.destroyed = false
    self._closing = false

    -- Install composition's lifecycle wrapper even for an empty node.
    self:has_component("_scene_init")
end

function node:get_id() return self._id end
function node:get_name() return self._name end
function node:get_scene() return self._scene end
function node:get_parent() return self._parent end
function node:get_children() return copy_array(self._children) end

function node:create_child(name)
    return self._scene:create_node(name, self)
end

function node:set_parent(parent)
    local scene = self._scene
    scene:_assert_live_node(self)
    if (parent ~= nil) then scene:_assert_live_node(parent) end

    local ancestor = parent
    while (ancestor) do
        assert(ancestor ~= self, "scene parenting would create a cycle")
        ancestor = ancestor._parent
    end

    if (parent == self._parent) then return self end
    unlink(self)
    self._parent = parent
    local siblings = parent and parent._children or scene._roots
    siblings[#siblings + 1] = self
    return self
end

-- Snapshot in depth-first insertion order, excluding this node.
function node:find_descendants(selector)
    assert(selector == nil or type(selector) == "string" or type(selector) == "table",
        "component selector must be a name or cslib.class")
    local result, stack = {}, {}
    for i = #self._children, 1, -1 do stack[#stack + 1] = self._children[i] end
    while (#stack > 0) do
        local current = table.remove(stack)
        if (selector == nil or current:has_component(selector)) then result[#result + 1] = current end
        for i = #current._children, 1, -1 do stack[#stack + 1] = current._children[i] end
    end
    return result
end

function node:destroy()
    if (self.destroyed) then return end

    -- Freeze the entire subtree before user destructors can move siblings away.
    if (not self._closing) then
        self._closing = true
        for _, descendant in ipairs(self:find_descendants()) do descendant._closing = true end
    end
    self.destroyed = true

    local errors = {}
    local children = self:get_children()
    for i = #children, 1, -1 do
        local ok, err = xpcall(children[i].destroy, traceback, children[i])
        if (not ok) then errors[#errors + 1] = err end
    end

    local ok, err = xpcall(self.destroy_components, traceback, self)
    if (not ok) then errors[#errors + 1] = err end
    unlink(self)
    self._scene._nodes[self._id] = nil
    self._parent = nil
    if (#errors > 0) then error(table.concat(errors, "\n"), 0) end
end

lib.composition.apply(node)

local add_component = node.add_component
function node:add_component(name, component_class, ...)
    self._scene:_assert_live_node(self)
    return add_component(self, name, component_class, ...)
end

return node
