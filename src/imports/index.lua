--[[ Init ]]
assert(_VERSION:find("5.4"), "^1[ Please enable Lua 5.4 ]^0")

local is_server = IsDuplicityVersion()

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

for key, value in pairs(lib._event) do
    if (value ~= nil) then
        lib[key] = value
    end
end

lib.uuid = lib.random.uuid

-- common functions
lib.coalesce = lib.common.coalesce
