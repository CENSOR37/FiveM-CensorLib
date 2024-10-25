--[[ Init ]]
if (not _VERSION:find("5.4")) then error("^1[ Please enable Lua 5.4 ]^0", 2) end

local is_server = IsDuplicityVersion()

lib.is_server = is_server
lib.is_client = not is_server
