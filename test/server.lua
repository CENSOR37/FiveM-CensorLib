-- CreateThread(function()
--     -- using callback, can be access by after and done
--     Wait(500)
--     local player_src = 1

--     cslib.callback("request.remote", player_src, "test_val").after(function(msg, num)
--         print("request.remote 1", msg, num)
--     end)

--     local cb_handler = cslib.callback("request.remote", player_src, "test_val")
--     cb_handler.done(function(msg, num)
--         print("request.remote 2", msg, num)
--     end)

--     -- using await
--     local msg, num = cslib.callback("request.remote", player_src, "test_val").await()
--     print("request.remote 3", msg, num)
-- end)



-- local function benchmark(fn, times, ...)
--     local start = os.nanotime()
--     for i = 1, times, 1 do
--         fn(...)
--     end
--     local finish = os.nanotime()
--     local as_milliseconds = (finish - start) / 1000000
--     return as_milliseconds
-- end


-- local _GetEntityCoords = GetEntityCoords
-- local native = {
--     get_entity_coords = GetEntityCoords,
-- }

-- cslib.set_timeout(function()
--     local ped = GetPlayerPed(1)
--     local times = 1024*10
--     print("Benchmarking of GetEntityCoords", benchmark(GetEntityCoords, times, ped))
--     print("Benchmarking of _GetEntityCoords", benchmark(_GetEntityCoords, times, ped))
--     print("Benchmarking of native.get_entity_coords", benchmark(native.get_entity_coords, times, ped))
-- end, 1000)

