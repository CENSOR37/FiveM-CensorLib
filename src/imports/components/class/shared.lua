-- a huge courtesy to overextended team

local getinfo = debug.getinfo

local mixins = {}
local constructors = {}

local function get_constructor(class)
    local constructor = constructors[class] or class.constructor

    if (class.constructor) then
        constructors[class] = class.constructor
        class.constructor = nil
    end

    return constructor
end

local function void() return "" end


function mixins.new(class, ...)
    lib.validate.type.assert(class, "table")

    local constructor = get_constructor(class)
    local private = {}
    local obj = setmetatable({ private = private }, class)

    -- START OF: super constructor
    -- This is to allow the constructor to call super constructors
    if (constructor) then
        local parent = class

        rawset(obj, "super", function(self, ...)
            parent = getmetatable(parent)
            constructor = get_constructor(parent)

            if constructor then return constructor(self, ...) end
        end)

        constructor(obj, ...)
    end

    rawset(obj, "super", nil)
    -- END OF: super constructor

    -- START OF: private fields
    if (private ~= obj.private or next(obj.private)) then
        private = table.clone(obj.private)

        table.wipe(obj.private)

        setmetatable(obj.private, {
            __metatable = "private",
            __tostring = void,
            __index = function(self, index)
                local di = getinfo(2, "n")

                if (di.namewhat ~= "method" and di.namewhat ~= "") then return end

                return private[index]
            end,
            __newindex = function(self, index, value)
                local di = getinfo(2, "n")

                if (di.namewhat ~= "method" and di.namewhat ~= "") then
                    error(("cannot set value of private field '%s'"):format(index), 2)
                end

                private[index] = value
            end,
        })
    else
        obj.private = nil
    end
    -- END OF: private fields

    return obj
end

local function class(...)
    local class = table.clone(mixins)
    class.__index = class

    return class
end

local function extends(derived)
    lib.validate.type.assert(derived, "table")

    local class = class()

    setmetatable(class, derived)

    return class
end

lib_module = setmetatable({
    extends = extends,
}, {
    __call = function(_, ...)
        return class(...)
    end,
})
