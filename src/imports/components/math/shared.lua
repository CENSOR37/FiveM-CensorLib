---@class csmath : mathlib
local math = math

function math.lerp(a, b, t)
    return a + (b - a) * t
end

function math.clamp(val, lower, upper)                    -- credit overextended, https://love2d.org/forums/viewtopic.php?t=1856
    if lower > upper then lower, upper = upper, lower end -- swap if boundaries supplied the wrong way
    return math.max(lower, math.min(upper, val))
end

function math.groupdigits(number, seperator) -- credit overextended, http://richard.warburton.it
    local left, num, right = string.match(number, "^([^%d]*%d)(%d*)(.-)$")
    return left .. (num:reverse():gsub("(%d%d%d)", "%1" .. (seperator or ",")):reverse()) .. right
end

function math.round(value, places) -- credit overextended
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" then error("Value must be a number") end

    if places then
        if type(places) == "string" then places = tonumber(places) end
        if type(places) ~= "number" then error("Places must be a number") end

        if places > 0 then
            local mult = 10 ^ (places or 0)
            return math.floor(value * mult + 0.5) / mult
        end
    end

    return math.floor(value + 0.5)
end

lib_module = math
