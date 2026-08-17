local setmetatable = setmetatable
local table_wipe = table.wipe

-- unique marker for a slot whose entry was removed, can never collide with a user key
local TOMBSTONE = setmetatable({}, { __tostring = function() return "<removed>" end })

-- Map class: ordered key-value map
--
-- Entries are packed into one flat array, a key at `2n - 1` followed by its value at
-- `2n`, and `index` maps a key straight to the offset of its value. A lookup is a
-- single array read, a key sits next to its value while walking the map, and the whole
-- thing costs one table per map instead of one table per entry.
--
-- A removal blanks its slot with a tombstone instead of shifting the array down, and
-- the array is compacted only once the dead slots outnumber the live ones, which makes
-- delete O(1) amortized rather than the O(n) shift plus index rebuild an array needs.
local map = {}
map.__index = map

function map:__len()
    return self.size
end

function map:__tostring()
    return string.format("Map(%d)", self.size)
end

function map.new()
    return setmetatable({
        entries = {}, -- 2n - 1 -> key, 2n -> value
        index = {},   -- key -> offset of its value
        size = 0,     -- live entries
        slots = 0,    -- occupied slots, live entries plus tombstones
        locks = 0,    -- running walks, compaction is held back while one is in flight
    }, map)
end

--- Drop the tombstones and pull the remaining entries to the front
--- Moves entries around, so do not call it while iterating the map
---@return table self
local function compact(self)
    local slots, size = self.slots, self.size
    if (slots == size) then return self end

    local entries, index = self.entries, self.index
    local last = slots * 2
    local target = 0

    for i = 1, last, 2 do
        local key = entries[i]

        if (key ~= TOMBSTONE) then
            target = target + 2

            if (target ~= i + 1) then
                entries[target - 1] = key
                entries[target] = entries[i + 1]
                index[key] = target
            end
        end
    end

    for i = target + 1, last do
        entries[i] = nil
    end

    self.slots = size

    return self
end

map.compact = compact

function map.from_array(array)
    local self = map.new()

    for i = 1, #array do
        local entry = array[i]
        assert(type(entry) == "table", "map constructor requires a table with two elements")

        self:set(entry[1], entry[2])
    end

    return self
end

--- Clear all entries in the map
---@return table self
function map:clear()
    if (self.locks == 0) then
        table_wipe(self.entries)
        self.slots = 0
    else
        -- a walk is reading the array, blank the slots in place rather than pull them
        -- away from under it, the walk compacts them off on its way out
        local entries = self.entries

        for pos = 2, self.slots * 2, 2 do
            entries[pos - 1] = TOMBSTONE
            entries[pos] = nil
        end
    end

    table_wipe(self.index)
    self.size = 0

    return self
end

--- Delete an entry by key, safe to call while walking the map
---@param key string|number|boolean
---@return boolean true if entry existed and was removed
function map:delete(key)
    local index = self.index
    local pos = index[key]
    if not (pos) then return false end

    local entries = self.entries
    local slots = self.slots
    local size = self.size - 1
    local unlocked = self.locks == 0

    index[key] = nil
    self.size = size

    if (unlocked and pos == slots * 2) then
        -- entry sits at the tail, drop it along with any tombstones it uncovers
        -- while a walk is running the array only ever grows, so this waits
        repeat
            entries[pos] = nil
            entries[pos - 1] = nil

            slots = slots - 1
            pos = pos - 2
        until (slots == 0 or entries[pos - 1] ~= TOMBSTONE)

        self.slots = slots

        -- keep the dead slots from piling up
        if (slots > size * 2) then compact(self) end
    else
        entries[pos - 1] = TOMBSTONE
        entries[pos] = nil

        if (unlocked and slots > size * 2) then compact(self) end
    end

    return true
end

--- Call a function for each key-value pair, in insertion order
--- Entries may be set or deleted from within the callback, additions are walked too
---@param func fun(key: any, value: any)
---@return nil
function map:for_each(func)
    local entries = self.entries
    local locks = self.locks + 1
    local n = 0

    self.locks = locks

    -- walked in passes so the slot count stays out of the inner loop, a callback that
    -- appends entries just leaves another pass to run, and the lock means nothing it
    -- removes can move a slot the walk has yet to reach
    repeat
        local last = self.slots * 2

        for pos = n + 2, last, 2 do
            local key = entries[pos - 1]

            if (key ~= TOMBSTONE) then
                func(key, entries[pos])
            end
        end

        n = last
    until (self.slots * 2 <= n)

    locks = locks - 1
    self.locks = locks

    -- walking already cost a pass over the slots, so settle any dead ones while here
    if (locks == 0) then
        compact(self)
    end
end

--- Retrieve a value by key
---@param key string|number|boolean
---@return any
function map:get(key)
    local pos = self.index[key]
    if not (pos) then return nil end

    return self.entries[pos]
end

--- Check if a key exists
---@param key string|number|boolean
---@return boolean
function map:has(key)
    return self.index[key] ~= nil
end

--- Check if the map holds no entries
---@return boolean
function map:is_empty()
    return self.size == 0
end

--- Set a value for a key (insert or update), new keys are appended at the end
---@param key string|number|boolean
---@param value any
---@return table self
function map:set(key, value)
    if (key == nil) then error("map key cannot be nil", 2) end

    local entries = self.entries
    local pos = self.index[key]

    if (pos) then
        entries[pos] = value
    else
        local slots = self.slots + 1

        pos = slots * 2
        entries[pos - 1] = key
        entries[pos] = value
        self.index[key] = pos

        self.slots = slots
        self.size = self.size + 1
    end

    return self
end

--- Retrieve the key and value at an ordered position, negative counts from the end
---@param position number
---@return any key, any value
function map:at(position)
    local size = self.size

    if (position < 0) then
        position = size + position + 1
    end

    if (position < 1 or position > size) then return nil end

    local entries = self.entries

    -- no tombstones in the way, the position maps straight onto a slot
    if (self.slots == size) then
        local pos = position * 2

        return entries[pos - 1], entries[pos]
    end

    local live = 0

    for n = 1, self.slots do
        local pos = n * 2
        local key = entries[pos - 1]

        if (key ~= TOMBSTONE) then
            live = live + 1

            if (live == position) then
                return key, entries[pos]
            end
        end
    end
end

--- Stateful iterator over the key-value pairs, in insertion order
--- Unlike for_each this does not hold back compaction, so do not delete while iterating
---@return fun(): any, any
function map:iterator()
    local entries = self.entries
    local n = 0

    return function()
        while (n < self.slots) do
            n = n + 1

            local pos = n * 2
            local key = entries[pos - 1]

            if (key ~= TOMBSTONE) then
                return key, entries[pos]
            end
        end
    end
end

map.__pairs = map.iterator

--- Copy the entries out as an array of `{key, value}` pairs
---@param buffer table? table to fill instead of allocating one
---@return table
function map:array(buffer)
    local array = buffer or {}
    local entries = self.entries
    local live = 0

    for n = 1, self.slots do
        local pos = n * 2
        local key = entries[pos - 1]

        if (key ~= TOMBSTONE) then
            live = live + 1
            array[live] = { key, entries[pos] }
        end
    end

    return array
end

--- Copy the keys out as an array, in insertion order
---@param buffer table? table to fill instead of allocating one
---@return table
function map:key_array(buffer)
    local array = buffer or {}
    local entries = self.entries
    local live = 0

    for n = 1, self.slots do
        local key = entries[n * 2 - 1]

        if (key ~= TOMBSTONE) then
            live = live + 1
            array[live] = key
        end
    end

    return array
end

--- Copy the values out as an array, in insertion order
---@param buffer table? table to fill instead of allocating one
---@return table
function map:value_array(buffer)
    local array = buffer or {}
    local entries = self.entries
    local live = 0

    for n = 1, self.slots do
        local pos = n * 2

        if (entries[pos - 1] ~= TOMBSTONE) then
            live = live + 1
            array[live] = entries[pos]
        end
    end

    return array
end

-- ALIASES
map.remove = map.delete
map.empty = map.clear

lib_module = setmetatable({
    new = map.new,
    from_array = map.from_array,
}, {
    __call = function(_, ...)
        local args = { ... }

        return map.from_array(args)
    end,
})
