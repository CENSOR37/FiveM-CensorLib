local data = require "data.collect"
local collect_effect = require "src.modules.collect.client"
local burst = {}

local function clear_burst()
    for i = 1, #burst do burst[i]:destroy() end
    burst = {}
end

RegisterCommand("curvecollect", function(_, args)
    clear_burst()
    local requested = tonumber(args[1]) or 12
    if (requested ~= requested) then requested = 12 end
    local count = math.max(1, math.min(24, math.floor(requested)))
    local ped = PlayerPedId()
    if (not DoesEntityExist(ped)) then return end

    for i = 1, count do
        local angle = (i - 1) / count * math.pi * 2
        local radius = 2.2 + (i % 3) * 0.35
        local position = GetOffsetFromEntityInWorldCoords(ped,
            math.cos(angle) * radius, math.sin(angle) * radius, -0.8)
        burst[i] = collect_effect.new(data.model, position, ped,
            data.duration + ((i - 1) % 6) * 100, math.deg(angle))
    end
end, false)

RegisterCommand("curvecollect_stop", clear_burst, false)
