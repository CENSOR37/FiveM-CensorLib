local lua_assert = assert
local validate = {}

function validate.type(value, ...)
    local num_types = select("#", ...)
    if (num_types == 0) then
        return false, "no types specified"
    end

    local value_type = type(value)
    local need = ""

    for i = 1, num_types do
        local validate_type = select(i, ...)
        lua_assert(type(validate_type) == "string", "bad argument types, only expected string") -- should never use anyhing else than string
        need = need .. (i > 1 and ", " or "") .. validate_type

        if (value_type == validate_type) then
            return true
        end
    end

    return false, ("bad value (%s expected, got %s)"):format(need, value_type)
end

lib_module = setmetatable({}, {
    __index = function(_, key)
        local medthod = validate[key]

        lua_assert(medthod, ("method validate.%s not found"):format(key))

        return setmetatable({}, {
            __call = function(_, ...)
                return medthod(...)
            end,
            __index = function(_, key)
                if (key ~= "assert") then return nil end

                return function(...)
                    local result, error_message = medthod(...)
                    lua_assert(result, error_message)
                end
            end,
        });
    end,
});
