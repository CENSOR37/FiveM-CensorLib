-- Run from censorlib: lua tests/scene_graph.lua
-- Real class/composition modules, with minimal FiveM compatibility shims.
local stop_handlers = {}
local lib = {
    validate = { type = { assert = function(value, expected)
        assert(type(value) == expected, "expected " .. expected)
    end } },
    resource = { on_stop = function(callback) stop_handlers[#stop_handlers + 1] = callback end },
}
package.loaded["src.imports._lib.shared"] = lib
table.clone = function(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end
table.wipe = function(value)
    for key in pairs(value) do value[key] = nil end
end
local file = assert(io.open("src/imports/class/shared.lua", "r"))
local source = file:read("*a")
file:close()
-- Normalize only the existing FiveM compound assignment for stock Lua.
source = source:gsub("level %+= 1", "level = level + 1")
lib.class = assert(load(source, "@src/imports/class/shared.lua"))()
lib.composition = require "src.imports.composition.shared"
local scene = require "src.imports._scene.shared"

local passed = 0
local function test(name, callback)
    local ok, err = xpcall(callback, debug.traceback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end
local function fails(callback, message)
    local ok, err = pcall(callback)
    assert(not ok, "expected failure: " .. message)
    assert(tostring(err):find(message, 1, true), tostring(err))
end
local component = lib.class()
function component:constructor(value)
    assert(self.owner and self.owner:get_scene())
    self.value = value
    self.destroy_count = 0
end
function component:destroy()
    assert(self.owner)
    self.destroy_count = self.destroy_count + 1
end

test("hierarchy, snapshots, IDs and cycle rejection", function()
    local world = scene:new()
    local a, b = world:create_node("a"), world:create_node("b")
    local child = a:create_child("child")
    local grandchild = child:create_child("grandchild")
    assert(world:get_node(child:get_id()) == child)
    assert(a:find_descendants()[2] == grandchild)
    local snapshot = a:get_children()
    snapshot[1] = nil
    assert(#a:get_children() == 1)
    fails(function() a:set_parent(grandchild) end, "cycle")
    fails(function() a:set_parent(a) end, "cycle")
    assert(a:get_parent() == nil and child:get_parent() == a)
    child:set_parent(b)
    assert(#a:get_children() == 0 and grandchild:get_parent() == child)
    child:set_parent(nil)
    assert(#world:get_roots() == 3)
    local id = child:get_id()
    child:destroy()
    assert(world:get_node(id) == nil and grandchild.destroyed)
    assert(world:create_node("new"):get_id() > id)
    world:destroy()
end)

test("foreign and destroyed parents leave graph intact", function()
    local world, other = scene:new(), scene:new()
    local a, b = world:create_node("a"), other:create_node("b")
    fails(function() a:set_parent(b) end, "belong")
    fails(function() world:create_node("bad", b) end, "belong")
    assert(#world:find_nodes() == 1)
    b:destroy()
    fails(function() other:create_node("bad", b) end, "belong")
    a:destroy()
    fails(function() a:add_component("late", component) end, "belong")
    world:destroy()
    fails(function() world:create_node("late") end, "destroyed")
    other:destroy()
end)

test("composition queries, exact classes, ownership and removal", function()
    local world = scene:new()
    local a = world:create_node("a")
    local b = a:create_child("b")
    local first = a:add_component("one", component, 1)
    local second = a:add_component("two", component, 2)
    b:add_component("one", component, 3)
    assert(first.owner == a and first.value == 1)
    assert(#a:get_components(component) == 2)
    fails(function() a:get_component(component) end, "multiple")
    fails(function() a:add_component("one", component) end, "already in use")
    assert(#world:find_nodes(component) == 2)
    assert(a:find_descendants("one")[1] == b)
    assert(#world:find_nodes(lib.class.extends(component)) == 0)
    assert(a:remove_component("one"))
    assert(first.destroy_count == 1 and first.owner == nil)
    world:destroy()
    world:destroy()
    a:destroy()
    assert(second.destroy_count == 1 and second.owner == nil)
    assert(#world:find_nodes() == 0)
end)

test("child-first cleanup survives destructor errors", function()
    local order = {}
    local tracked = lib.class()
    function tracked:constructor(label, should_fail) self.label, self.should_fail = label, should_fail end
    function tracked:destroy()
        order[#order + 1] = self.label
        if (self.should_fail) then error("cleanup failure") end
    end
    local world = scene:new()
    local root = world:create_node("root")
    root:add_component("first", tracked, "parent-first")
    root:add_component("last", tracked, "parent-last", true)
    root:create_child("child"):add_component("tracked", tracked, "child", true)
    fails(function() world:destroy() end, "cleanup failure")
    assert(table.concat(order, ",") == "child,parent-last,parent-first")
    assert(#world:find_nodes() == 0 and #world:get_roots() == 0)
    world:destroy()
end)

test("subtree cannot escape or grow during destruction", function()
    local world = scene:new()
    local root, outside = world:create_node("root"), world:create_node("outside")
    local sibling = root:create_child("sibling")
    local guard = lib.class()
    function guard:destroy()
        fails(function() sibling:set_parent(outside) end, "being destroyed")
        fails(function() sibling:create_child("late") end, "being destroyed")
        fails(function() sibling:add_component("late", component) end, "being destroyed")
        root:destroy()
    end
    root:create_child("last"):add_component("guard", guard)
    root:destroy()
    assert(sibling.destroyed and #world:find_nodes() == 1)
    world:destroy()
end)

test("prefab hierarchy and isolated arguments including nil", function()
    local observer = lib.class()
    function observer:constructor(config, absent, value)
        assert(#self.owner:get_children() == 1)
        assert(absent == nil and value == 42)
        self.config = config
        self.config.count = self.config.count + 1
    end
    function observer:destroy() end
    local prefab = { name = "shop", components = {
        { name = "observer", class = observer, args = table.pack({ count = 0 }, nil, 42) },
    }, children = { { name = "door", components = { { name = "lock", class = component, args = { true } } } } } }
    local world = scene:new()
    local parent = world:create_node("district")
    local a, b = world:instantiate(prefab, parent), world:instantiate(prefab)
    assert(a:get_parent() == parent and b:get_parent() == nil)
    assert(a:get_component("observer").config.count == 1)
    assert(b:get_component("observer").config.count == 1)
    assert(prefab.components[1].args[1].count == 0)
    assert(a:get_children()[1]:get_component("lock").value == true)
    world:destroy()
end)

test("invalid prefab definitions fail before allocation", function()
    local world = scene:new()
    local cyclic = { name = "cycle" }
    cyclic.children = { cyclic }
    fails(function() world:instantiate(cyclic) end, "cycle")
    fails(function() world:instantiate({ name = "bad", children = { [2] = { name = "hole" } } }) end, "dense")
    fails(function() world:instantiate({ name = "bad", components = {
        { name = "same", class = component }, { name = "same", class = component },
    } }) end, "duplicate")
    assert(#world:find_nodes() == 0)
    assert(world:create_node("first"):get_id() == 1)
    world:destroy()
end)

test("failed prefab cleans completed components and moved nodes", function()
    local world = scene:new()
    local outside = world:create_node("outside")
    local instance
    local good = lib.class.extends(component)
    function good:constructor()
        self:super(true)
        instance = self
        self.owner:set_parent(outside)
    end
    local broken = lib.class()
    function broken:constructor() error("construction failure") end
    function broken:destroy() end
    fails(function() world:instantiate({ name = "prefab", children = {
        { name = "moved", components = { { name = "good", class = good } } },
        { name = "broken", components = { { name = "broken", class = broken } } },
    } }) end, "construction failure")
    assert(instance.destroy_count == 1 and instance.owner == nil)
    assert(#world:find_nodes() == 1 and #outside:get_children() == 0)
    world:destroy()
end)

test("constructor destroying its owner does not leak", function()
    local world = scene:new()
    local cleaned = 0
    local suicidal = lib.class()
    function suicidal:constructor() self.owner:destroy() end
    function suicidal:destroy() cleaned = cleaned + 1 end
    fails(function() world:instantiate({ name = "gone", components = {
        { name = "suicidal", class = suicidal },
    } }) end, "destroyed during component construction")
    assert(cleaned == 1 and #world:find_nodes() == 0)
    world:destroy()
end)

test("yielded constructor cleaned after scene destruction", function()
    local world = scene:new()
    local current = world:create_node("async")
    local cleaned = 0
    local yielding = lib.class()
    function yielding:constructor() coroutine.yield() end
    function yielding:destroy() cleaned = cleaned + 1 end
    local co = coroutine.create(function() current:add_component("yielding", yielding) end)
    assert(coroutine.resume(co))
    world:destroy()
    local ok, err = coroutine.resume(co)
    assert(not ok and tostring(err):find("destroyed during component construction", 1, true))
    assert(cleaned == 1 and #world:find_nodes() == 0)
end)

test("failed prefab freezes children created by constructors", function()
    local world = scene:new()
    local outside = world:create_node("outside")
    local dynamic
    local guard = lib.class()
    function guard:destroy()
        fails(function() dynamic:set_parent(outside) end, "being destroyed")
    end
    local builder = lib.class()
    function builder:constructor()
        dynamic = self.owner:create_child("dynamic")
        self.owner:create_child("guard"):add_component("guard", guard)
    end
    function builder:destroy() end
    local broken = lib.class()
    function broken:constructor() error("construction failure") end
    function broken:destroy() end
    fails(function() world:instantiate({ name = "prefab", components = {
        { name = "builder", class = builder }, { name = "broken", class = broken },
    } }) end, "construction failure")
    assert(dynamic.destroyed and #world:find_nodes() == 1)
    world:destroy()
end)

test("opt-in demo runs against the actual scene module", function()
    cslib = lib
    lib._scene = scene
    dofile("examples/scene_graph/shared.lua")
end)
test("resource stop cleans all scenes despite errors", function()
    local a, b = scene:new(), scene:new()
    local broken = lib.class()
    function broken:destroy() error("stop failure") end
    a:create_node("a"):add_component("broken", broken)
    local retained = b:create_node("b"):add_component("good", component)
    assert(#stop_handlers == 1)
    fails(stop_handlers[1], "stop failure")
    assert(a.destroyed and b.destroyed and retained.destroy_count == 1)
    assert(#a:find_nodes() == 0 and #b:find_nodes() == 0)
    fails(function() scene:new() end, "stopping")
end)

print(("Scene graph: %d tests passed (%s)"):format(passed, _VERSION))
