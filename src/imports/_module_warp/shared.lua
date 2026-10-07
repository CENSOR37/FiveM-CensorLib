local validate = require "src.imports.validate.shared"

-- WARNING: this factory warp assume it self in first argument or calling "class:new" not "class.new"
local function _module_class_warp(in_class, in_out)
    validate.type.assert(in_class, "table")
    validate.type.assert(in_class.new, "function")
    validate.type.assert(in_out, "table", "nil")

    local out = in_out or {}

    function out.new(first, ...)
        if (first == out) then
            return in_class:new(...)
        end

        return in_class:new(first, ...)
    end

    setmetatable(out, {
        __call = function(_, ...)
            return in_class:new(...)
        end,
    })

    return out
end

-- WARNING: this factory warp assume it self in first argument or calling "class:new" not "class.new"
local function factory_warp(export_table, in_class)
    validate.type.assert(in_class, "table")
    validate.type.assert(in_class.new, "function")

    return function(first, ...)
        if (first == export_table) then
            return in_class:new(...)
        end

        return in_class:new(first, ...)
    end
end

local exp = {}

exp.module_class_warp = _module_class_warp
exp.factory_warp = factory_warp

return exp
