local promise = promise
local citizen_await = Citizen.Await
local table_unpack = table.unpack
local is_server = lib.is_server
local on_remote = is_server and lib.on_client or lib.on_server

local prefix = "cslib.cb"
local timeout_time = 10 * 1000

local function register_callback(eventname, listener)
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    return on_remote(cb_eventname, function(id, ...)
        local src = source

        if (is_server) then
            lib.emit_client(id, src, listener(...))
        else
            lib.emit_server(id, listener(...))
        end
    end)
end

local function trigger_callback_to_server(eventname, listener, ...)
    lib.validate.type.assert(listener, "function", "table")

    local callback_id = lib.random.uuid()
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    lib.once_server(callback_id, listener)
    lib.emit_server(cb_eventname, callback_id, ...)
end

local function trigger_callback_to_client(eventname, src, listener, ...)
    lib.validate.type.assert(src, "number", "string")
    lib.validate.type.assert(listener, "function", "table")

    local callback_id = lib.random.uuid()
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    lib.once_client(callback_id, listener)
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
