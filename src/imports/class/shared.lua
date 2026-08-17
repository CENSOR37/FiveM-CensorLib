-- a huge courtesy to overextended team

local getinfo = debug.getinfo

local weakkeys = { __mode = "k" }

local classes = setmetatable({}, weakkeys)

local mixins = {}
local constructors = setmetatable({}, weakkeys)

local function get_constructor(class)
    local cached = constructors[class]
    if (cached ~= nil) then
        return cached.fn, cached.owner
    end

    local current = class
    while (current) do
        local ctor = rawget(current, "constructor")
        if (ctor) then
            constructors[class] = { fn = ctor, owner = current }
            return ctor, current
        end
        current = getmetatable(current)
    end
end

local function void() return "" end

local function find_owner(class, fn)
    local current = class

    while (current) do
        local methods = classes[current]

        if (methods) then
            if (not methods[fn]) then
                for name, value in pairs(current) do
                    if (value == fn) then
                        methods[fn] = name
                        break
                    end
                end
            end

            if (methods[fn]) then return current end
        end

        current = getmetatable(current)
    end
end

local function find_inherited(class, fn, key)
    local current = getmetatable(find_owner(class, fn) or class)

    while (current) do
        local value = rawget(current, key)
        if (value ~= nil) then return value end

        current = getmetatable(current)
    end
end

local function validate_private_access(class)
    local level = 3

    while true do
        local di = getinfo(level, "f")

        if (not di or not di.func) then return false end
        if (find_owner(class, di.func)) then return true end

        level += 1
    end
end

local function get_super(obj, class)
    return setmetatable({}, {
        __metatable = "super",
        __tostring = void,

        __index = function(_, key)
            local value = find_inherited(class, getinfo(2, "f").func, key)

            if (type(value) ~= "function") then return value end

            return function(_, ...) return value(obj, ...) end
        end,

        __call = function(_, _, ...)
            local owner = find_owner(class, getinfo(2, "f").func) or class
            local parent = getmetatable(owner)
            local constructor = parent and get_constructor(parent)

            if (constructor) then return constructor(obj, ...) end
        end,
    })
end

function mixins.new(class, ...)
    lib.validate.type.assert(class, "table")

    local constructor = get_constructor(class)
    local private = {}
    local obj = setmetatable({ private = private }, class)

    if (constructor) then constructor(obj, ...) end

    -- START OF: private fields
    if (private ~= obj.private or next(obj.private)) then
        private = table.clone(obj.private)

        table.wipe(obj.private)

        setmetatable(obj.private, {
            __metatable = "private",
            __tostring = void,
            __index = function(self, index)
                if (not validate_private_access(class)) then return end

                return private[index]
            end,
            __newindex = function(self, index, value)
                if (not validate_private_access(class)) then
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

    classes[class] = setmetatable({}, weakkeys)

    class.__index = function(obj, key)
        if (key == "super") then return get_super(obj, class) end

        local current = class

        while (current) do
            local value = rawget(current, key)
            if (value ~= nil) then return value end

            current = getmetatable(current)
        end
    end

    return class
end

local function extends(derived)
    lib.validate.type.assert(derived, "table")

    local class = class()

    setmetatable(class, derived)

    return class
end

return setmetatable({
    extends = extends,
}, {
    __call = function(_, ...)
        return class(...)
    end,
})
