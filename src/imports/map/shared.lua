local table_wipe = table.wipe

local class = require "src.imports.class.shared"
local factory_warp = require "src.imports._factory_warp.shared"

-- Map class: ordered key-value map
local map = class()

function map:__len()
    return self.size
end

function map:constructor()
    self.data = {}
    self.index = {}
    self.size = 0

    self:clear()
end

function map.from_array(array)
    local self = map:new()

    for i = 1, #array do
        local value = array[i]
        assert(#value == 2, "map constructor requires a table with two elements")

        self:set(value[1], value[2])
    end

    return self
end

--- Clear all entries in the map
--- @return nil
function map:clear()
    table_wipe(self.data)
    table_wipe(self.index)

    self.size = 0
end

--- Delete an entry by key
---@param key string|number|boolean
---@return boolean true if entry existed and was removed
function map:delete(key)
    local pos = self.index[key]
    if not (pos) then return false end

    -- remove element from data array
    table.remove(self.data, pos)
    self.size -= 1

    -- rebuild index for all entries
    table_wipe(self.index)
    for i, entry in ipairs(self.data) do
        self.index[entry.key] = i
    end

    return true
end

--- Call a function for each key-value pair
---@param func function
---@return nil
function map:for_each(func)
    for i = 1, self.size, 1 do
        local entry = self.data[i]

        func(entry.key, entry.value)
    end
end

--- Retrieve a value by key
---@param key string|number|boolean
---@return any
function map:get(key)
    local pos = self.index[key]

    return pos and self.data[pos].value or nil
end

--- Check if a key exists
---@param key string|number|boolean
---@return boolean
function map:has(key)
    return self.index[key] ~= nil
end

--- Set a value for a key (insert or update)
---@param key string|number|boolean
---@param value any
---@return nil
function map:set(key, value)
    local pos = self.index[key]

    if (pos) then
        self.data[pos].value = value
    else
        local entry = { key = key, value = value }
        table.insert(self.data, entry)

        self.size += 1
        self.index[key] = self.size
    end
end

local factory = factory_warp(map)

return setmetatable({
    new = factory,
    from_array = map.from_array,
    class = map,
}, {
    __call = function(_, ...)
        local args = { ... }

        return map.from_array(args)
    end,
})
