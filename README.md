# censorlib

censorlib is a Lua library for FiveM that provides a functions, classes, utilities and more.

## Requirements

- Lua 5.4 in your manifest

## Installation

To use `censorlib` load imports file into your resource in your manifest file.

```lua
shared_script "@censorlib/imports.lua"
```

## module prefix with "\_" is considered private or experimental, breaking change is expected.

## Experimental scene graph

`cslib._scene` provides resource-local nodes, component ownership, hierarchy
queries, and reusable Lua prefab definitions. See [the guide](docs/scene_graph.md)
for the API and an opt-in demo.
