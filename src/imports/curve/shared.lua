local curve = {}
curve.__index = curve

local function is_finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function auto_tangents(keys)
    local tangents = {}
    for i = 1, #keys do
        local tangent = 0
        if (i > 1 and i < #keys) then
            local previous, current, following = keys[i - 1], keys[i], keys[i + 1]
            local before = current[2] - previous[2]
            local after = following[2] - current[2]
            -- Keep endpoints, turning points, and transitions to flat segments level.
            if ((before > 0 and after > 0) or (before < 0 and after < 0)) then
                tangent = (following[2] - previous[2]) / (following[1] - previous[1])
            end
        end
        tangents[i] = tangent
    end
    return tangents
end

local function create(keys, mode)
    assert(type(keys) == "table" and #keys > 0, "curve requires at least one key")

    local count = #keys
    for index in pairs(keys) do
        assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= count, "curve keys must be a dense array")
    end

    local copied_keys = {}
    for i = 1, count do
        local key = keys[i]
        assert(type(key) == "table" and #key == 2 and is_finite(key[1]) and is_finite(key[2]), "curve keys must be { input, value } pairs of finite numbers")
        copied_keys[i] = { key[1], key[2] }
    end

    table.sort(copied_keys, function(a, b) return a[1] < b[1] end)

    for i = 2, count do
        assert(copied_keys[i - 1][1] ~= copied_keys[i][1], "curve key inputs must be unique")
    end

    return setmetatable({
        _keys = copied_keys,
        _mode = mode,
        _tangents = mode == "cubic" and auto_tangents(copied_keys) or nil,
    }, curve)
end

function curve:evaluate(input)
    assert(is_finite(input), "curve input must be a finite number")

    local keys = self._keys
    if (input <= keys[1][1]) then return keys[1][2] end
    if (input >= keys[#keys][1]) then return keys[#keys][2] end

    for i = 2, #keys do
        local right = keys[i]
        if (input == right[1]) then return right[2] end

        if (input < right[1]) then
            local left = keys[i - 1]
            if (self._mode == "constant") then return left[2] end

            local span = right[1] - left[1]
            local t = (input - left[1]) / span
            if (self._mode == "cubic") then
                -- Cubic Hermite interpolation; tangent slopes are in value / input units.
                local t2, t3 = t * t, t * t * t
                return (2 * t3 - 3 * t2 + 1) * left[2]
                    + (t3 - 2 * t2 + t) * span * self._tangents[i - 1]
                    + (-2 * t3 + 3 * t2) * right[2]
                    + (t3 - t2) * span * self._tangents[i]
            end

            return left[2] * (1 - t) + right[2] * t
        end
    end
end

local constructors = {
    linear = function(keys)
        return create(keys, "linear")
    end,

    constant = function(keys)
        return create(keys, "constant")
    end,

    cubic = function(keys)
        return create(keys, "cubic")
    end,
}

-- Earlier constructor names use the same keyframe behavior.
constructors.step = constructors.constant
constructors.bezier = constructors.cubic

return constructors
