local lib = require "src.imports._lib.shared"

-- this will convert value into a scalar value between 0 and 1 based on the min and max values provided
local function normalize(val, min, max)
    min = min or 0
    max = max or 100
    if min == max then return 0 end

    local t = (val - min) / (max - min)
    return math.max(0, math.min(1, t))
end

local function is_true(val)
    return val ~= nil and (val == true or val == 1)
end

local round = lib.math.round

local PlayerPedId = PlayerPedId
local IsEntityDead = IsEntityDead
local GetEntityHealth = GetEntityHealth
local GetPedArmour = GetPedArmour
local GetCurrentPedWeapon = GetCurrentPedWeapon
local GetVehiclePedIsIn = GetVehiclePedIsIn
local DoesEntityExist = DoesEntityExist
local GetPedInVehicleSeat = GetPedInVehicleSeat
local GetVehicleMaxNumberOfPassengers = GetVehicleMaxNumberOfPassengers
local IsPedSprinting = IsPedSprinting
local IsPedRagdoll = IsPedRagdoll
local IsPedSwimming = IsPedSwimming
local IsPedClimbing = IsPedClimbing
local IsPedJumping = IsPedJumping

local states = {}

local function find_or_create_state(key)
    if not states[key] then
        local state = lib.state:new()
        state:subscribe(function(val, prev)
            TriggerEvent(("cslib:cache:%s"):format(key), val, prev)
        end)
        states[key] = state
    end
    return states[key]
end

exports("cache", function(key)
    return states[key] and states[key].value
end)

-- BEGIN OF SETTER
local function do_poll()
    local ped = PlayerPedId()
    local player_id = PlayerId()
    find_or_create_state("ped"):set(ped)

    find_or_create_state("dead"):set(is_true(IsEntityDead(ped)))
    find_or_create_state("health"):set(GetEntityHealth(ped))
    find_or_create_state("armour"):set(GetPedArmour(ped))

    local has_weapon, weapon_hash = GetCurrentPedWeapon(ped, true)
    find_or_create_state("armed"):set(is_true(has_weapon)) -- Lua can return 1 or true depending on game build
    find_or_create_state("weapon"):set(is_true(has_weapon) and weapon_hash or false)

    local veh = GetVehiclePedIsIn(ped, false)
    local inveh = DoesEntityExist(veh)

    if (inveh) then
        find_or_create_state("vehicle"):set(veh)

        if (GetPedInVehicleSeat(veh, -1) == ped) then
            find_or_create_state("seat"):set(-1)
        else
            local found_seat = nil
            for i = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                if (GetPedInVehicleSeat(veh, i) == ped) then
                    found_seat = i
                    break
                end
            end
            find_or_create_state("seat"):set(found_seat ~= nil and found_seat or false)
        end
    else
        find_or_create_state("vehicle"):set(false)
        find_or_create_state("seat"):set(false)
    end

    find_or_create_state("sprinting"):set(is_true(IsPedSprinting(ped)))
    find_or_create_state("ragdoll"):set(is_true(IsPedRagdoll(ped)))
    find_or_create_state("swimming"):set(is_true(IsPedSwimming(ped)))
    find_or_create_state("climbing"):set(is_true(IsPedClimbing(ped)))
    find_or_create_state("jumping"):set(is_true(IsPedJumping(ped)))
    find_or_create_state("stamina"):set(round(GetPlayerStamina(player_id), 2))
    find_or_create_state("underwater_time"):set(round(GetPlayerUnderwaterTimeRemaining(player_id), 2))
    find_or_create_state("is_talking"):set(is_true(NetworkIsPlayerTalking(player_id)))
end

do_poll()
lib.set_interval(do_poll, 100)

return states