local promise = promise
local citizen_await = Citizen.Await
local table_unpack = table.unpack
local on_remote = lib.is_server and lib.on_client or lib.on_server

local prefix = "cslib.cb"
local timeout_time = 10 * 1000

local function register_callback(eventname, listener)
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    return on_remote(cb_eventname, function(id, ...)
        local src = source

        if (lib.is_server) then
            lib.emit_client(id, src, listener(...))
        else
            lib.emit_server(id, listener(...))
        end
    end)
end

local function trigger_callback(eventname, src, listener, ...)
    local callback_id = lib.random.uuid()
    local cb_eventname = ("%s:%s"):format(prefix, eventname)

    if (lib.is_server) then
        lib.validate.type.assert(src, "number", "string")
        lib.validate.type.assert(listener, "function", "table")

        lib.once_client(callback_id, listener)
        lib.emit_client(cb_eventname, src, callback_id, ...)
    else
        -- if client triggering server callback src or player id is not required
        -- src is going to be listener
        lib.validate.type.assert(src, "function", "table")

        lib.once_server(callback_id, src)
        lib.emit_server(cb_eventname, callback_id, listener, ...)
    end
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

        if (lib.is_server) then
            trigger_callback(eventname, src, handler, ...)
        else
            trigger_callback(eventname, handler, src, ...)
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
        return lib.taskify(trigger_callback_await)(...)
    end,
})
