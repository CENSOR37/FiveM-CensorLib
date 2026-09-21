# Curve collect

A local visual demo inspired by `gc_collect_effect.lua`: gold bars pop up, sweep sideways, spin, and shrink into the player's chest. Six shared curves control pull, lift, sway, scale, rotation, and light intensity.

## Run in FiveM

Copy this `curve-collect` folder into your server's resources directory as a separate resource. Start it after censorlib:

```cfg
ensure censorlib
ensure curve-collect
```

In chat, use `/curvecollect` for 12 objects, `/curvecollect 24` for a larger burst, or `/curvecollect_stop` to cancel. In F8, omit the slash. Try walking while they fly toward you. Running the command again replaces the previous burst.

This resource is not started or added to server configuration automatically. It creates local cosmetic props only and does not grant items or money.

## Reuse

Copy `data/collect.lua` and `src/modules/collect/client.lua` into a resource that imports censorlib, and list them in that resource's manifest `files`. The module keeps the reference script's constructor argument order:

```lua
local collect_effect = require "src.modules.collect.client"
local effect = collect_effect.new("prop_gold_bar", position, PlayerPedId(), 1800, 0)
-- effect:destroy() cancels it early.
```

Edit the keyframes in `data/collect.lua` to change the feel. Inputs run from 0 to 1 across the animation; duration is in milliseconds. Lift and sway values are meters, spin is degrees, and scale is a multiplier.

Position is calculated from the original spawn point and the current target on every frame. Scale uses a fresh matrix each frame. Animation starts after the object loads. One shared tick handles all active effects and stops when idle; effects clean up when finished, cancelled, when their parent disappears, or when the resource stops.

The conversation preview uses samples evaluated by the real Lua curves and a schematic scene. It is not footage from FiveM. Native rendering, model scale, lighting, and terrain placement still require an in-game check.

Standalone mocked lifecycle checks: from the censorlib root, run `lua examples/curve-collect/tests/collect.lua`.

Native references: [ped bone position](https://github.com/citizenfx/natives/blob/master/PED/GetPedBoneCoords.md), [point light](https://github.com/citizenfx/natives/blob/master/GRAPHICS/DrawLightWithRange.md).
