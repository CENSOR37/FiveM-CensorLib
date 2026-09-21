-- Opt-in: shared_script "@censorlib/examples/scene_graph/shared.lua"
-- Load @censorlib/imports.lua first. No GTA entities or network events.
local switch = cslib.class()

function switch:constructor(enabled)
    self.enabled = enabled
end

function switch:toggle()
    self.enabled = not self.enabled
    print(("[scene demo] %s enabled: %s"):format(self.owner:get_name(), tostring(self.enabled)))
end

function switch:destroy()
    print(("[scene demo] cleaned %s"):format(self.owner:get_name()))
end

local shop_prefab = {
    name = "shop",
    children = {
        { name = "door", components = { { name = "lock", class = switch, args = { true } } } },
        { name = "alarm", components = { { name = "power", class = switch, args = { false } } } },
    },
}

local scene = cslib._scene:new()
local district = scene:create_node("district")
local shop = scene:instantiate(shop_prefab, district)
local door = shop:find_descendants("lock")[1]
door:get_component("lock"):toggle()

local second_shop = scene:instantiate(shop_prefab)
assert(second_shop:find_descendants("lock")[1]:get_component("lock").enabled)
assert(#scene:find_nodes(switch) == 4)

shop:destroy()
assert(#scene:find_nodes(switch) == 2)
scene:destroy()
print("[scene demo] complete")
