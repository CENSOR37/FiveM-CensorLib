-- https://gist.github.com/Egor-Skriptunoff/375ffe05075063c9a2ce61bb30b1ce50

local math_floor = math.floor
local pseudo_number = {}
pseudo_number.__index = pseudo_number

local const = {
    param_mul_8  = (function()
        local g, m, d = 1, 128, 2 * 110 + 1
        repeat
            g, m, d = g * g * (d >= m and 3 or 1) % 257, m / 2, d % m
        until m < 1
        return g
    end)(),
    param_mul_45 = 58 * 4 + 1,
    param_add_45 = 3580861008710 * 2 + 1,
}

function pseudo_number.new(seed)
    lib.validate.type.assert(seed, "number")

    local self = {}
    self.seed = seed
    self.state_45 = seed % 35184372088832
    self.state_8 = math_floor(seed / 35184372088832) % 255 + 2

    return setmetatable(self, pseudo_number)
end

function pseudo_number:get_seed()
    return (self.state_8 - 2) * 35184372088832 + self.state_45
end

function pseudo_number:next()
    self.state_45 = (self.state_45 * const.param_mul_45 + const.param_add_45) % 35184372088832

    repeat
        self.state_8 = self.state_8 * const.param_mul_8 % 257
    until self.state_8 ~= 1

    local r = self.state_8 % 32
    local n = math_floor(self.state_45 / 2 ^ (13 - (self.state_8 - r) / 32)) % 2 ^ 32 / 2 ^ r
    return math_floor(n % 1 * 2 ^ 32) + math_floor(n)
end

lib_module.number = setmetatable({ new = pseudo_number.new }, { __call = function(_, ...) return pseudo_number.new(...) end })
