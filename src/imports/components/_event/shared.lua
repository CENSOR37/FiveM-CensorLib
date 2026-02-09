local msgpack_pack_args = msgpack.pack_args
local is_server = IsDuplicityVersion()

local function add_event_handler(event_name, listener, is_remote)
    if (is_remote) then
        RegisterNetEvent(event_name)
    end
    return AddEventHandler(event_name, listener)
end

local function add_net_handler(event_name, listener)
    return add_event_handler(event_name, listener, true)
end

local function bind_once(event_name, listener, is_remote)
    local handler
    handler = add_event_handler(event_name, function(...)
        RemoveEventHandler(handler)
        listener(...)
    end, is_remote)
    return handler
end

local event = {}
event.on = AddEventHandler
event.off = RemoveEventHandler
event.emit = TriggerEvent
event.once = function(event_name, listener)
    return bind_once(event_name, listener, false)
end

if (is_server) then
    event.on_client = add_net_handler
    event.emit_client = function(event_name, target, ...)
        assert(target > 0, "Target client ID must be greater than 0, or use emit_all_clients instead.")
        TriggerClientEvent(event_name, target, ...)
    end
    event.emit_client_latent = TriggerLatentClientEvent

    event.once_client = function(event_name, listener)
        return bind_once(event_name, listener, true)
    end

    event.emit_all_clients = function(event_name, ...)
        TriggerClientEvent(event_name, -1, ...)
    end

    event.emit_all_clients_latent = function(event_name, bps, ...)
        TriggerLatentClientEvent(event_name, -1, bps, ...)
    end

    event.emit_clients = function(event_name, clients, ...)
        local payload = msgpack_pack_args(...)
        local payload_len = #payload

        for i = 1, #clients do
            TriggerClientEventInternal(event_name, clients[i], payload, payload_len)
        end
    end

    event.emit_clients_latent = function(event_name, clients, bps, ...)
        local payload = msgpack_pack_args(...)
        local payload_len = #payload
        bps = bps or 25000

        for i = 1, #clients do
            TriggerLatentClientEventInternal(event_name, clients[i], payload, payload_len, bps)
        end
    end
else
    event.on_server = add_net_handler
    event.emit_server = TriggerServerEvent
    event.emit_server_latent = TriggerLatentServerEvent

    event.once_server = function(event_name, listener)
        return bind_once(event_name, listener, true)
    end
end

lib_module = event
