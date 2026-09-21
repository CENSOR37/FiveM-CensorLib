# Experimental scene graph

`cslib._scene` is an opt-in, resource-local Lua hierarchy for gameplay objects.
The underscore marks an experimental API that may change. It works on either
side of FiveM, but client and server scenes are independent.

This version provides ownership, components, queries, and prefab instantiation.
Parenting controls lifetime only. Transforms, GTA attachments, rendering,
spatial streaming, persistence, and replication are not implemented. Loading
the module creates no GTA entities, tick loops, or network events.

## Try it

After loading `@censorlib/imports.lua`, add this to a test resource's manifest:

```lua
shared_script "@censorlib/examples/scene_graph/shared.lua"
```

The demo instantiates two shops, toggles one door's logical lock, checks that
the other is independent, and destroys both. Output goes to the console; it
has no in-world visuals. A shared script runs separately on client and server.

## Define behavior and reusable content

Components use ordinary `cslib.class` classes with `destroy()`, through the
existing `cslib.composition` module. `self.owner` is the node, available during
construction and destruction; composition clears it after destruction.

```lua
local lock = cslib.class()

function lock:constructor(config)
    self.locked = config.locked
end

function lock:destroy()
    -- Release any timers, events, or objects acquired by this component.
end

local prefab = {
    name = "shop",
    children = {
        {
            name = "door",
            components = {
                { name = "lock", class = lock, args = { { locked = true } } },
            },
        },
    },
}

local scene = cslib._scene:new()
local district = scene:create_node("district")
local shop = scene:instantiate(prefab, district)
local door = shop:find_descendants("lock")[1]
door:get_component("lock").locked = false

shop:set_parent(nil) -- Move to scene roots; it remains owned by the scene.
district:destroy()   -- The shop now survives this destruction.
scene:destroy()      -- Destroys every remaining node and component.
```

Keep definitions in your resource's `data` directory and reusable component
classes in modules. Prefabs are Lua definitions containing class references,
not a JSON or network serialization format.

## API

| Scene method | Result |
| --- | --- |
| `cslib._scene:new()` | New scene, tracked until destruction or resource stop |
| `scene:create_node(name, parent?)` | New node; omitted parent creates a root |
| `scene:get_node(id)` | Node, or nil after destruction |
| `scene:get_roots()` | Snapshot array of roots |
| `scene:find_nodes(selector?)` | All matching nodes, including roots |
| `scene:instantiate(definition, parent?)` | Root node of a fresh prefab instance |
| `scene:destroy()` | Idempotent cleanup of the whole scene |

| Node method | Result |
| --- | --- |
| `node:get_id()`, `get_name()`, `get_scene()`, `get_parent()` | Node metadata |
| `node:get_children()` | Snapshot array of immediate children |
| `node:create_child(name)` | New child in the same scene |
| `node:set_parent(parent_or_nil)` | Reparent, or move to scene roots |
| `node:find_descendants(selector?)` | Matching descendants, excluding self |
| `node:add_component(name, class, ...)` | Owned component instance |
| `node:get_component(selector)` | Matching component or nil |
| `node:get_components(class)` | All components of that exact class |
| `node:has_component(selector)` | Whether a component matches |
| `node:remove_component(selector)` | Destroy component; return whether found |
| `node:destroy()` | Destroy this subtree and its components |

A selector is a component name or exact class reference. Omit it for unfiltered
node queries. Class matching does not include subclasses. Multiple components
may share a class under different names; singular lookup/removal by class errors
if ambiguous. Node names need not be unique. IDs are scene-local, monotonically
increasing, and not reused; they are not persistent or network IDs.

Queries return snapshots in depth-first insertion order. Reparented nodes are
appended to their new siblings. Mutating a returned array does not edit the graph.
Do not write internal `_` fields, `destroyed`, or replace node lifecycle methods.

## Lifecycle and failure behavior

- Cross-scene parenting, cycles, and parenting to destroyed nodes are rejected.
- A subtree is closed to additions and reparenting before destructors run.
- Children are destroyed before parents, in reverse sibling order. Components
  are destroyed in reverse attachment order by `cslib.composition`.
- Cleanup continues after destructor errors, unregisters nodes, then reports
  the collected errors. Repeated destruction is safe.
- Resource stop destroys all remaining scenes, even if one reports an error.
  Explicitly destroy scenes when finished; the module retains live scenes.

Prefab `children` and `components` must be dense arrays. Each node requires a
non-empty `name`; component names must be unique within their node. `args` is
an argument array, or `table.pack(...)` to preserve nil arguments. Plain data
tables in arguments are deeply copied per instantiation. Shared table references
within one definition remain shared within its instance. Class references are
retained. Metatable-backed argument tables are rejected; functions and non-table
values are passed through unchanged.

Definitions are validated before node creation. The complete hierarchy is then
created, and components are attached in preorder and definition order. A
constructor can inspect sibling nodes, but their components may not exist yet.
Instantiation does not provide a separate start/activation phase.

If construction fails, all nodes created by that instantiation and their
successfully attached components are destroyed, including nodes that a
constructor reparented. This is cleanup, not a transaction: external side effects
are not rolled back. A constructor that throws must release its own partially
acquired resources; the existing composition module does not call `destroy()`
on failed constructors. Avoid yielding in constructors; if one yields, its
partial instance is not yet attached, and cleanup can finish only when it resumes.

## Verification

From the library directory, run:

```text
lua tests/scene_graph.lua
```

The harness runs the real class and composition implementations. It supplies
small FiveM API shims and normalizes the existing class module's compound
assignment for stock Lua. This checks logical behavior outside the game;
the opt-in demo is the in-runtime smoke test.
