local lua_assert = assert
local validate = {}

function validate.type(value, ...)
    local types = { ... }
    if (#types == 0) then return true end

    local map_type = {}
    for i = 1, #types, 1 do
        local validate_type = types[i]
        lua_assert(type(validate_type) == "string", "bad argument types, only expected string") -- should never use anyhing else than string
        map_type[validate_type] = true
    end

    local value_type = type(value)

    local matches = (map_type[value_type] ~= nil)

    if not (matches) then
        local require_types = table.concat(types, ", ")
        local error_message = ("bad value (%s expected, got %s)"):format(require_types, value_type)

        return false, error_message
    end

    return true
end

cslib_component = setmetatable({}, {
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
