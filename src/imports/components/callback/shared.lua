local promise = promise
local citizen_await = Citizen.Await
local table_unpack = table.unpack
local is_server = lib.is_server
local on_remote = is_server and lib.on_client or lib.on_server

local prefix = "cslib.cb"
local timeout_time = 10 * 1000

local invoke_event = ("cslib.cb.invoke:%s"):format(lib.resource.name)
local pending_callbacks = {}

on_remote(invoke_event, function(id, ...)
    if not (is_server) then
        if source == "" then return end
    end

    local listener = pending_callbacks[id]

    if not (listener) then return end

    pending_callbacks[id] = nil

    listener(...)
end)

local function create_listener(eventname, listener, src)
    local id

    repeat
        if (is_server) then
            id = ("%s:%s:%s"):format(eventname, math.random(0, 1000000), src)
        else
            id = ("%s:%s"):format(eventname, math.random(0, 1000000))
        end
    until not pending_callbacks[id]

    pending_callbacks[id] = listener

    return id
end

local function register_callback(eventname, listener)
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    return on_remote(cb_eventname, function(id, ...)
        local src = source

        if (is_server) then
            lib.emit_client(invoke_event, src, id, listener(...))
        else
            lib.emit_server(invoke_event, id, listener(...))
        end
    end)
end

local function trigger_callback_to_server(eventname, listener, ...)
    lib.validate.type.assert(listener, "function", "table")

    local callback_id = create_listener(eventname, listener)
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    lib.emit_server(cb_eventname, callback_id, ...)
end

local function trigger_callback_to_client(eventname, src, listener, ...)
    lib.validate.type.assert(src, "number", "string")
    lib.validate.type.assert(listener, "function", "table")

    local callback_id = create_listener(eventname, listener, src)
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    lib.emit_client(cb_eventname, src, callback_id, ...)
end

local function trigger_callback_await(eventname, src, ...)
    local function handler(...)
        local p = promise.new()

        local handler = function(...)
            p:resolve({
                success = true,
                params = { ... },
            })
        end

        if (is_server) then
            trigger_callback_to_client(eventname, src, handler, ...)
        else
            trigger_callback_to_server(eventname, handler, src, ...)
        end

        lib.set_timeout(function()
            p:resolve({
                success = false,
            })
        end, timeout_time)

        return citizen_await(p)
    end

    local return_values = handler(...)

    if not (return_values.success) then return end

    return table_unpack(return_values.params)
end

lib_module = setmetatable({
    register = register_callback,
}, {
    __call = function(_, ...)
        return lib.async(trigger_callback_await)(...)
    end,
})
