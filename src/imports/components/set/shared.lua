local table_wipe = table.wipe

local set = {}
set.__index = set

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
    if (self:has(value)) then return end

    local index = #self.data + 1
    self.data[index] = value
    self.index[value] = index
    self.size = self.size + 1
end

function set:clear()
    self.data = table_wipe(self.data)
    self.index = table_wipe(self.index)
    self.size = 0
end

function set:delete(value)
    if not (self:has(value)) then return false end

    local index = self.index[value]
    local last_index = #self.data
    local last_value = self.data[last_index]

    if (index ~= last_index) then
        self.data[index] = last_value
        self.index[last_value] = index
    end

    self.data[last_index] = nil
    self.index[value] = nil

    self.size = self.size - 1

    return true
end

function set:for_each(callback_fn)
    for i = 1, self.size do
        local value = self.data[i]
        callback_fn(value)
    end
end

function set:array()
    local array = {}
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

lib_module = setmetatable({
    new = set.new,
    from_array = set.from_array,
}, {
    __call = function(_, ...)
        return set.new(...)
    end,
})
