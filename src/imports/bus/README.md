# `cslib.bus` - Hybrid Message Bus

A high-performance, feature-rich Pub/Sub message bus and RPC module for FiveM and `censorlib`.

## Features

- **Hybrid Scope**: Seamless intra-resource (local) messaging and inter-boundary (client <-> server) network messaging with adaptive payload compression.
- **Fast Topic Routing**: Direct O(1) exact-topic dispatch with optional compiled wildcard pattern matching (`*` and `**`).
- **Priority & FIFO Execution**: Configurable listener priority with stable ordering and cancelable propagation (`return false`).
- **Request / Reply (RPC)**: Synchronous awaitable (`:await()`) and asynchronous callback (`:callback()`) pattern for both local and network request-response.
- **Instantiable & Singleton**: Use the default shared bus `cslib.bus` or create isolated instances via `cslib.bus.new()`.
- **Flexible Syntax**: Supports both colon (`bus:emit()`) and dot (`bus.emit()`) calling syntax.
- **Clean Subscriptions**: `bus:on()` returns an `unsub()` function for easy teardown.

---

## 1. Basic Pub / Sub (Local)

```lua
-- Subscribe to a topic
local unsub = cslib.bus:on("player:spawn", function(player_data)
    print("Player spawned:", player_data.name)
end)

-- Publish an event
cslib.bus:emit("player:spawn", { name = "John", id = 1 })

-- Unsubscribe anytime
unsub()
```

### Listen Once (`once`)
```lua
cslib.bus:once("resource:ready", function()
    print("This will execute only once!")
end)
```

---

## 2. Topic Wildcards

Topics can be delimited with `:`, `.`, or `/`.

- `*`: Matches a single topic segment.
- `**`: Matches multiple topic segments across delimiters.

```lua
-- Single-segment wildcard
cslib.bus:on("inventory:*", function(item)
    -- Matches "inventory:add", "inventory:remove"
    -- Does NOT match "inventory:item:modify"
end)

-- Multi-segment wildcard
cslib.bus:on("player:**", function(...)
    -- Matches "player:login", "player:inventory:slot:move", etc.
end)

-- Catch all events
cslib.bus:on("*", function(...)
    local current_topic = cslib.bus.current_topic
    print("Event occurred:", current_topic)
end)
```

---

## 3. Priority & Cancellation

Listeners with higher priority numbers execute first (default: `0`).

```lua
-- High priority filter / guard (runs first)
cslib.bus:on("item:use", function(item)
    if item.is_broken then
        print("Item is broken! Cancelling event.")
        return false -- Stops further listeners from executing!
    end
end, 100)

-- Normal listener (runs only if not cancelled)
cslib.bus:on("item:use", function(item)
    print("Applying item effect...")
end, 0)
```

---

## 4. Request / Reply Pattern (Local RPC)

Register a responder and request data using coroutine await or callbacks:

```lua
-- Register responder
cslib.bus:reply("inventory:get_weight", function(player_id)
    local weight = calculate_weight(player_id)
    return weight, 50.0 -- returns current, max
end)

-- Inside a coroutine / thread:
CreateThread(function()
    local weight, max_weight = cslib.bus:request_await("inventory:get_weight", 1)
    -- or:
    local weight, max_weight = cslib.bus:request("inventory:get_weight", 1):await()
    print("Current weight:", weight, "Max:", max_weight)
end)

-- Or using callback:
cslib.bus:request("inventory:get_weight", 1):callback(function(weight, max_weight)
    print("Got weight asynchronously:", weight)
end)
```

---

## 5. Network Messaging (Client <-> Server)

### From Client:
```lua
-- Send to server
cslib.bus:emit_server("inventory:use_item", item_id)

-- Request from server and await response
CreateThread(function()
    local items = cslib.bus:request_server("inventory:get_all"):await()
    print("Got items from server:", #items)
end)

-- Listen to messages from server
cslib.bus:on_server("inventory:sync", function(inventory)
    print("Synced inventory from server")
end)

-- Reply to requests from server
cslib.bus:reply_server("player:get_ped_coords", function()
    return GetEntityCoords(PlayerPedId())
end)
```

### From Server:
```lua
-- Listen to messages from clients (first parameter is player source)
cslib.bus:on_client("inventory:use_item", function(src, item_id)
    print("Player", src, "used item", item_id)
end)

-- Reply to client requests (first parameter is player source)
cslib.bus:reply_client("inventory:get_all", function(src)
    return get_player_inventory(src)
end)

-- Send to a specific client
cslib.bus:emit_client("inventory:sync", target_client_id, inventory_data)

-- Send to all clients
cslib.bus:emit_all_clients("announcement:broadcast", "Server restarting in 5m")

-- Request from a client and await response
CreateThread(function()
    local coords = cslib.bus:request_client("player:get_ped_coords", target_client_id):await()
    print("Player coords:", coords)
end)
```

### Unified / Broadcast:
```lua
-- Broadcasts locally AND across network (to server if client, to all clients if server)
cslib.bus:broadcast("weather:changed", "rain")

-- Listen to remote messages regardless of client/server side
cslib.bus:on_remote("chat:message", function(...) end)
```

---

## 6. Middlewares & Interceptors

```lua
-- Log all events matching a pattern
cslib.bus:use("inventory:*", function(topic, ...)
    print(("[AUDIT] Event '%s' triggered"):format(topic))
end)

-- Returning false in a middleware cancels the event before any listener runs
cslib.bus:use(function(topic, ...)
    if is_server_locked then
        return false
    end
end)
```

---

## 7. Isolated Bus Instances

```lua
-- Create an independent message bus
local ui_bus = cslib.bus.new("ui")

ui_bus:on("modal:open", function(modal_name)
    -- Will only trigger for ui_bus, completely isolated from default bus
end)

ui_bus:emit("modal:open", "inventory")
```
