local native = {
    register_net_event = RegisterNetEvent,
    add_event_handler = AddEventHandler,
    remove_event_handler = RemoveEventHandler,
    trigger_event = TriggerEvent,
    trigger_server_event = TriggerServerEvent,
    trigger_client_event = TriggerClientEvent,
    is_duplicity_version = IsDuplicityVersion,
    get_invoking_resource = GetInvokingResource,
    trigger_latent_server_event = TriggerLatentServerEvent,
    trigger_latent_client_event = TriggerLatentClientEvent,
    trigger_client_event_internal = TriggerClientEventInternal,
}

local is_server = IsDuplicityVersion()
local msgpack_pack_args = msgpack.pack_args

local function create_evnet_handler(listener, is_local_ctx)
    return function(...)
        local src = source
        local is_from_remote = false
        local should_proceed = false

        if (is_server) then
            is_from_remote = src ~= ""
        else
            is_from_remote = src == 65535
        end

        if (is_from_remote and not is_local_ctx) then
            should_proceed = true
        elseif (not is_from_remote and is_local_ctx) then
            should_proceed = true
        end

        if (should_proceed) then
            listener(...)
        end
    end
end

local function on_local(eventName, listener)
    local handler = create_evnet_handler(listener, true)

    return native.add_event_handler(eventName, handler)
end

local function on_remote(eventName, listener)
    local handler = create_evnet_handler(listener, false)

    return native.register_net_event(eventName, handler)
end

local function bind_once(is_remote, eventname, listener)
    local event

    local handler = function(...)
        lib.off(event)
        listener(...)
    end

    event = is_remote and on_remote(eventname, handler) or on_local(eventname, handler)

    return event
end

lib_module = {
    on = on_local,
    off = native.remove_event_handler,
    emit = native.trigger_event,
    [("emit_%s"):format(lib.service_inversed)] = is_server and native.trigger_client_event or native.trigger_server_event,
    [("emit_%s_latent"):format(lib.service_inversed)] = is_server and native.trigger_latent_client_event or native.trigger_latent_server_event,
    emit_all_clients = is_server and function(eventname, ...) return native.trigger_client_event(eventname, -1, ...) end or nil,
    emit_all_clients_latent = is_server and function(eventname, bps, ...) return native.trigger_latent_client_event(eventname, -1, bps, ...) end or nil,
    once = function(eventname, listener) return bind_once(false, eventname, listener) end,
    [("on_%s"):format(lib.service_inversed)] = on_remote,
    [("once_%s"):format(lib.service_inversed)] = function(eventname, listener) return bind_once(true, eventname, listener) end,
    emit_clients = is_server and function(eventname, clients, ...)
        local payload = msgpack_pack_args(...)
        local payload_len = payload:len()

        for i = 1, #clients do
            native.trigger_client_event_internal(eventname, clients[i], payload, payload_len)
        end
    end or nil,
    emit_clients_latent = is_server and function(eventname, clients, bps, ...)
        local payload = msgpack_pack_args(...)
        local payload_len = payload:len()

        for i = 1, #clients do
            native.trigger_latent_client_event(eventname, clients[i], bps, payload, payload_len)
        end
    end or nil,
}
