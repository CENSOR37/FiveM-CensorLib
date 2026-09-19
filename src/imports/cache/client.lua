--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.
--- Adaptations from ox_lib are subject to its original license.
--- https://github.com/overextended/ox_lib/blob/main/init.lua - See original file for license details.

local CreateThreadNow = Citizen.CreateThreadNow

local exp = exports["censorlib"]

local cache = {}
cache.player_id = PlayerId()
cache.server_id = GetPlayerServerId(cache.player_id)
cache.resource = GetCurrentResourceName()

local cache_listeners = {}
local bound_events = {}

local function init_cache_key(key)
    if (not bound_events[key]) then
        bound_events[key] = true
        cache_listeners[key] = {}

        AddEventHandler(("cslib:cache:%s"):format(key), function(val, prev)
            cache[key] = val
            local events = cache_listeners[key]
            if (events) then
                for i = 1, #events do
                    local cb = events[i]
                    CreateThreadNow(function()
                        cb(val, prev)
                    end)
                end
            end
        end)
    end
end

function cache.listen(key, callback)
    init_cache_key(key)

    table.insert(cache_listeners[key], callback)

    return function()
        local listeners = cache_listeners[key]
        if not (listeners) then return end

        for i, fn in ipairs(listeners) do
            if (fn == callback) then
                table.remove(listeners, i)
                break
            end
        end
    end
end

cache = setmetatable(cache, {
    __index = function(self, key)
        init_cache_key(key)
        local val = exp.cache(nil, key)
        rawset(self, key, val)
        return val
    end,
})

return cache
