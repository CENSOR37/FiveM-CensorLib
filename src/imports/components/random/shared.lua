local math_random = math.random
local string_format = string.format

local randomize_string = {
    charset = {
        numeric = { len = 0, chars = {} },
        upper = { len = 0, chars = {} },
        lower = { len = 0, chars = {} },
    },
}

do
    for i = 48, 57 do
        table.insert(randomize_string.charset.numeric.chars, string.char(i))
    end
    randomize_string.charset.numeric.len = #randomize_string.charset.numeric.chars
    for i = 65, 90 do
        table.insert(randomize_string.charset.upper.chars, string.char(i))
    end
    randomize_string.charset.upper.len = #randomize_string.charset.upper.chars
    for i = 97, 122 do
        table.insert(randomize_string.charset.lower.chars, string.char(i))
    end
    randomize_string.charset.lower.len = #randomize_string.charset.lower.chars
end

function randomize_string.random(length, options)
    if (length > 0) then
        options = options or { "lower", "upper", "numeric" }
        options.op_len = options.op_len or #options
        local char_type = options[math_random(1, options.op_len)]
        local new_char = randomize_string.charset[char_type].chars[math_random(1, randomize_string.charset[char_type].len)]

        return new_char .. randomize_string.random(length - 1, options)
    end

    return ""
end

local uuid = {
    { size = 0, chars = {} },
    { size = 0, chars = {} },
}

for i = 8, 0xb, 1 do
    local set = uuid[1]
    set.chars[#set.chars + 1] = string_format("%x", i)
    set.size = #set.chars
end

for i = 0, 0xf, 1 do
    local set = uuid[2]
    set.chars[#set.chars + 1] = string_format("%x", i)
    set.size = #set.chars
end

function uuid.random_char(position)
    if (position == 9) then return "-" end
    if (position == 14) then return "-" end
    if (position == 15) then return "4" end
    if (position == 19) then return "-" end
    if (position == 20) then return uuid[1].chars[math_random(1, uuid[1].size)] end
    if (position == 24) then return "-" end
    return uuid[2].chars[math_random(1, uuid[2].size)]
end

function uuid.random()
    local id = ""
    for i = 1, 36, 1 do
        id = id .. uuid.random_char(i)
    end

    return id
end

lib_module.string = setmetatable({ new = randomize_string.random }, { __call = function(_, ...) return randomize_string.random(...) end })
lib_module.uuid = setmetatable({ new = uuid.random }, { __call = function(_, ...) return uuid.random() end })

local chance_pool = {}
chance_pool.__index = chance_pool

function chance_pool.new()
    local self = setmetatable({}, chance_pool)
    self.pool = {}
    self.key = 10
    self.cumulative = 0
    return self
end

function chance_pool:calculate_cumulative()
    self.cumulative = 0

    for _, item in pairs(self.pool) do
        self.cumulative = self.cumulative + item.chance
        item.chance_end = self.cumulative
    end
end

function chance_pool:add_item(chance, data)
    lib.validate.type.assert(chance, "number")

    if not (data) then
        error("data is required")
    end

    self.key = self.key + 1
    self.pool[self.key] = { chance = chance, data = data }

    self:calculate_cumulative()

    return self.key
end

function chance_pool:remove_item(key)
    lib.validate.type.assert(key, "number")

    self.pool[key] = nil
    self:calculate_cumulative()
end

function chance_pool:random()
    if (self.cumulative == 0) then return nil end

    local random = math.random() * self.cumulative

    for _, value in pairs(self.pool) do
        if (random <= value.chance_end) then
            return value.data
        end
    end
end

lib_module.chance_pool = setmetatable({ new = chance_pool.new }, {
    __call = function()
        return chance_pool.new()
    end,
})
