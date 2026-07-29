local msgpack_pack_args = msgpack.pack_args
local is_server = IsDuplicityVersion()

-- TODO: make thoes convars
local LATENT_THRESHOLD <const> = 65536
local LATENT_TARGET_SEC <const> = 1.0
local LATENT_MIN_BPS <const> = 50000
local LATENT_MAX_BPS <const> = 500000

local function calc_bps(payload_len)
    local bps = math.ceil(payload_len / LATENT_TARGET_SEC)
    return math.min(math.max(bps, LATENT_MIN_BPS), LATENT_MAX_BPS)
end

local function pack_payload(...)
    local payload = msgpack_pack_args(...)
    local payload_len = #payload
    return payload, payload_len, payload_len >= LATENT_THRESHOLD
end

local function add_event_handler(event_name, listener, is_remote)
    if (is_remote) then
        return RegisterNetEvent(event_name, function(...)
            local src = source
            local is_from_remote = false

            if (is_server) then
                is_from_remote = (src ~= "")
            else
                is_from_remote = (src == 65535)
            end

            if (is_from_remote) then
                listener(...)
            end
        end)
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
        assert(type(target) == "number" or (type(target) == "string" and tonumber(target) ~= nil), "Target client ID must be a number or a string that can be converted to a number.")
        assert(tonumber(target) > 0, "Target client ID must be greater than 0, or use emit_all_clients instead.")
        TriggerClientEvent(event_name, target, ...)
    end

    event.emit_client_latent = function(event_name, target, bps, ...)
        assert(type(target) == "number" or (type(target) == "string" and tonumber(target) ~= nil), "Target client ID must be a number or a string that can be converted to a number.")
        assert(tonumber(target) > 0, "Target client ID must be greater than 0, or use emit_all_clients_latent instead.")
        TriggerLatentClientEvent(event_name, target, bps, ...)
    end

    event.emit_client_adaptive = function(event_name, target, ...)
        assert(type(target) == "number" or (type(target) == "string" and tonumber(target) ~= nil), "Target client ID must be a number or a string that can be converted to a number.")
        assert(tonumber(target) > 0, "Target client ID must be greater than 0, or use emit_all_clients_adaptive instead.")

        local payload, payload_len, is_latent = pack_payload(...)

        if (is_latent) then
            local bps = calc_bps(payload_len)
            TriggerLatentClientEventInternal(event_name, target, payload, payload_len, bps)
        else
            TriggerClientEventInternal(event_name, target, payload, payload_len)
        end
    end

    event.once_client = function(event_name, listener)
        return bind_once(event_name, listener, true)
    end

    event.emit_all_clients = function(event_name, ...)
        TriggerClientEvent(event_name, -1, ...)
    end

    event.emit_all_clients_latent = function(event_name, bps, ...)
        TriggerLatentClientEvent(event_name, -1, bps, ...)
    end

    event.emit_all_clients_adaptive = function(event_name, ...)
        local payload, payload_len, is_latent = pack_payload(...)

        if (is_latent) then
            local bps = calc_bps(payload_len)
            TriggerLatentClientEventInternal(event_name, -1, payload, payload_len, bps)
        else
            TriggerClientEventInternal(event_name, -1, payload, payload_len)
        end
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

    event.emit_clients_adaptive = function(event_name, clients, ...)
        local payload, payload_len, is_latent = pack_payload(...)

        if (is_latent) then
            local bps = calc_bps(payload_len)
            for i = 1, #clients do
                TriggerLatentClientEventInternal(event_name, clients[i], payload, payload_len, bps)
            end
        else
            for i = 1, #clients do
                TriggerClientEventInternal(event_name, clients[i], payload, payload_len)
            end
        end
    end
else
    event.on_server = add_net_handler
    event.emit_server = TriggerServerEvent
    event.emit_server_latent = TriggerLatentServerEvent

    event.emit_server_adaptive = function(event_name, ...)
        local payload, payload_len, is_latent = pack_payload(...)

        if (is_latent) then
            local bps = calc_bps(payload_len)
            TriggerLatentServerEventInternal(event_name, payload, payload_len, bps)
        else
            TriggerServerEventInternal(event_name, payload, payload_len)
        end
    end

    event.once_server = function(event_name, listener)
        return bind_once(event_name, listener, true)
    end
end

lib_module = event
