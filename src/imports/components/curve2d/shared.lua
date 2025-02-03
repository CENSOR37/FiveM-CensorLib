local function lerp(a, b, t)
    return a * (1 - t) + b * t
end

-- @ class curve key
local curve_key = {}
curve_key.__index = curve_key

function curve_key.new(in_time, in_value)
    return setmetatable({ time = in_time, value = in_value }, curve_key)
end

-- @ class curve
local curve = {}
curve.__index = curve

function curve.new(in_keys)
    local self = setmetatable({}, curve)
    self.keys = in_keys or {}

    table.sort(self.keys, function(a, b) return a.time < b.time end)

    return self
end

function curve:last_key()
    local key = self.keys[#self.keys]
    return { time = key.time, value = key.value }
end

function curve:first_key()
    local key = self.keys[1]
    return { time = key.time, value = key.value }
end

-- @ class linear
local linear_class = {}
linear_class.__index = linear_class
setmetatable(linear_class, { __index = curve })

function linear_class.new(...)
    local self = curve.new(...)

    assert(#self.keys >= 2, "linear curve requires at least 2 keys")

    return setmetatable(self, linear_class)
end

function linear_class:evaluate(in_time)
    if in_time <= self.keys[1].time then return self.keys[1].value end
    if in_time >= self.keys[#self.keys].time then return self.keys[#self.keys].value end

    for i = 1, #self.keys - 1 do
        local k1, k2 = self.keys[i], self.keys[i + 1]
        if in_time >= k1.time and in_time <= k2.time then
            local t = (in_time - k1.time) / (k2.time - k1.time)
            return k1.value + t * (k2.value - k1.value)
        end
    end
end

-- @ class bezier
local bezier_class = {}
bezier_class.__index = bezier_class
setmetatable(bezier_class, { __index = curve })

function bezier_class.new(...)
    local self = curve.new(...)

    assert(#self.keys >= 2, "bezier curve requires at least 2 keys")

    return setmetatable(self, bezier_class)
end

function bezier_class:evaluate(in_time)
    if in_time < 0 then in_time = 0 elseif in_time > 1 then in_time = 1 end

    local function bezier_recursive(points, t)
        if #points == 1 then return points[1].value end
        local newPoints = {}
        for i = 1, #points - 1 do
            newPoints[#newPoints + 1] = { value = lerp(points[i].value, points[i + 1].value, t) }
        end
        return bezier_recursive(newPoints, t)
    end

    return bezier_recursive(self.keys, in_time)
end

-- @ class constant
local constant_class = {}
constant_class.__index = constant_class
setmetatable(constant_class, { __index = curve })

function constant_class.new(...)
    local self = curve.new(...)

    assert(#self.keys >= 1, "constant curve requires at least 1 key")

    return setmetatable(self, constant_class)
end

function constant_class:evaluate(in_time)
    if in_time < self.keys[1].time then return self.keys[1].value end
    if in_time > self.keys[#self.keys].time then return self.keys[#self.keys].value end

    for i = 1, #self.keys - 1 do
        local k1, k2 = self.keys[i], self.keys[i + 1]
        if in_time >= k1.time and in_time <= k2.time then
            return k1.value
        end
    end
end

local classwarp = function(class, ...)
    return setmetatable({
        new = class.new,
    }, {
        __call = function(t, ...)
            return t.new(...)
        end,
    })
end

lib_module.key = classwarp(curve_key)
lib_module.linear = classwarp(linear_class)
lib_module.bezier = classwarp(bezier_class)
lib_module.constant = classwarp(constant_class)
