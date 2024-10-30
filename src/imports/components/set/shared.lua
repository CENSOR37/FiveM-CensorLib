local table_wipe = table.wipe

local set = {}
set.__index = set

function set.new(...)
    local self = {}
    self.data = {}
    self.index = {}
    self.length = 0

    self = setmetatable(self, set)
    self:empty()

    local args = { ... }
    for i = 1, #args do
        local value = args[i]
        self:add(value)
    end

    return self
end

function set.from_array(array)
    lib.validate.type.assert(array, "table")

    local self = set.new()
    for _, value in pairs(array) do
        self:add(value)
    end

    return self
end

function set:contain(value)
    return self.index[value] ~= nil
end

function set:contains(...)
    local args = { ... }

    for i = 1, #args do
        if not (self:contain(args[i])) then return false end
    end

    return true
end

function set:append(...)
    local args = { ... }
    for i = 1, #args do
        local other_set = args[i]
        lib.validate.type.assert(other_set, "table")
        lib.validate.type.assert(other_set.data, "table")

        for j = 1, #other_set.data do
            local value = other_set.data[j]
            self:add(value)
        end
    end
end

function set:array()
    local array = {}
    for i = 1, #self.data, 1 do
        local value = self.data[i]
        array[i] = value
    end
    return array -- return clone of data instead of reference
end

function set:add(value)
    lib.validate.type.assert(value, "string", "number", "boolean", "table")

    table.insert(self.data, value)
    self.index[value] = #self.data
    self.length = self.length + 1
end

function set:remove(value)
    lib.validate.type.assert(value, "string", "number", "boolean", "table")
    if not (self:contain(value)) then return end

    local index = self.index[value]
    table.remove(self.data, index)

    self.length = self.length - 1

    -- update index on remove
    self.index = table_wipe(self.index)
    for i = 1, #self.data do
        local value = self.data[i]
        if (value ~= nil) then
            self.index[value] = i
        end
    end
end

function set:size()
    return self.length
end

function set:empty()
    self.data = table_wipe(self.data)
    self.index = table_wipe(self.index)
    self.length = 0
end

lib_module = setmetatable({
    new = set.new,
    from_array = set.from_array,
}, {
    __call = function(_, ...)
        return set.new(...)
    end,
})
