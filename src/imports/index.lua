--[[ Init ]]
if (not _VERSION:find("5.4")) then error("^1[ Please enable Lua 5.4 ]^0", 2) end

local is_server = IsDuplicityVersion()

lib.is_server = is_server
lib.is_client = not is_server

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
