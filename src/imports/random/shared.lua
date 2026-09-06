local _uuid = require "src.imports._uuid.shared"

local math_random = math.random

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

return {
    string = setmetatable({ new = randomize_string.random }, { __call = function(_, ...) return randomize_string.random(...) end }),
    uuid = setmetatable({ new = _uuid.v7 }, { __call = function(_, ...) return _uuid.v7() end }),
}
