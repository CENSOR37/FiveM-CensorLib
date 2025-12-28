local setmetatable = setmetatable
local table_wipe = table.wipe

local set = {}
set.__index = set

function set:__len()
    return self.size
end

function set:__tostring()
    return string.format("Set(%d)", self.size)
end

function set.new(...)
    local self = {}
    self.data = {}
    self.index = {}
    self.size = 0

    self = setmetatable(self, set)

    local args = { ... }
    for i = 1, #args do
        local value = args[i]
        self:add(value)
    end

    return self
end

function set:has(value)
    return self.index[value] ~= nil
end

function set:add(value)
    if (value == nil) then return self end

    if (self.index[value]) then return self end

    local new_size = self.size + 1
    self.data[new_size] = value
    self.index[value] = new_size
    self.size = new_size

    return self
end

function set:clear()
    table_wipe(self.data)
    table_wipe(self.index)
    self.size = 0

    return self
end

function set:delete(value)
    local index = self.index[value]
    if not (index) then return false end

    local size = self.size
    local last_val = self.data[size]

    -- swap the last value into the deleted index
    if (index ~= size) then
        self.data[index] = last_val
        self.index[last_val] = index
    end

    self.data[size] = nil
    self.index[value] = nil
    self.size = size - 1

    return true
end

function set:for_each(callback_fn)
    for i = 1, self.size do
        callback_fn(self.data[i])
    end
end

function set:array(buffer)
    local array = buffer or {}
    for i = 1, self.size do
        array[i] = self.data[i]
    end
    return array
end

-- ALIASES
set.remove = set.delete
set.empty = set.clear

-- COMPATIBILITY, DEPRICATED WILL BE REMOVED
set.contain = set.has
set.contains = set.has

function set.from_array(array)
    local self = set.new()
    for i = 1, #array do
        local value = array[i]
        self:add(value)
    end

    return self
end

function set:iterator()
    local i = 0
    return function()
        i = i + 1
        if (i <= self.size) then
            return self.data[i]
        end
    end
end

lib_module = setmetatable({
    new = set.new,
    from_array = set.from_array,
}, {
    __call = function(_, ...)
        return set.new(...)
    end,
})
