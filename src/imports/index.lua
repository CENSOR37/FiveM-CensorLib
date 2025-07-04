--[[ Init ]]
assert(_VERSION:find("5.4"), "^1[ Please enable Lua 5.4 ]^0")

local msgpack_pack_args = msgpack.pack_args

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
local is_server = native.is_duplicity_version()

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

lib.is_server = is_server
lib.is_client = not is_server
lib.service = is_server and "server" or "client"
lib.service_inversed = is_server and "client" or "server"

lib.set_interval = function(handler, delay)
    return lib.timer.new(handler, delay, true)
end

lib.set_timeout = function(handler, delay)
    return lib.timer.new(handler, delay, false)
end

lib.on_tick = function(handler)
    return lib.timer.new(handler, 0, true)
end

lib.on_next_tick = function(handler)
    return lib.timer.new(handler, 0, false)
end

lib.on = on_local
lib.off = native.remove_event_handler
lib.emit = native.trigger_event
lib[("emit_%s"):format(lib.service_inversed)] = lib.is_server and native.trigger_client_event or native.trigger_server_event
lib[("emit_%s_latent"):format(lib.service_inversed)] = lib.is_server and native.trigger_latent_client_event or native.trigger_latent_server_event
lib.emit_all_clients = lib.is_server and function(eventname, ...) return native.trigger_client_event(eventname, -1, ...) end or nil
lib.once = function(eventname, listener) return bind_once(false, eventname, listener) end
lib[("on_%s"):format(lib.service_inversed)] = on_remote
lib[("once_%s"):format(lib.service_inversed)] = function(eventname, listener) return bind_once(true, eventname, listener) end
lib.emit_clients = lib.is_server and function(eventname, clients, ...)
    local payload = msgpack_pack_args(...)
    local payload_len = payload:len()

    for i = 1, #clients do
        native.trigger_client_event_internal(eventname, clients[i], payload, payload_len)
    end
end or nil

lib.uuid = lib.random.uuid

-- common functions
lib.coalesce = lib.common.coalesce
