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

function randomize_string.random(length, opts)
    if (length > 0) then
        opts = opts or { "lower", "upper", "numeric" }
        opts.op_len = opts.op_len or #opts
        local char_type = opts[math_random(1, opts.op_len)]
        local new_char = randomize_string.charset[char_type].chars[math_random(1, randomize_string.charset[char_type].len)]

        return new_char .. randomize_string.random(length - 1, opts)
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
