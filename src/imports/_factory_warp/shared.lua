local validate = require "src.imports.validate.shared"

-- WARNING: this factory warp assume it self in first argument or calling "class:new" not "class.new"
local function factory_warp(in_class)
    validate.type.assert(in_class, "table")
    validate.type.assert(in_class.new, "function")

    return function(first, ...)
        if (first == in_class) then
            return in_class:new(...)
        end

        return in_class:new(first, ...)
    end
end

return factory_warp
