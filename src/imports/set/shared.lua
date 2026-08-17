local setmetatable = setmetatable
local select = select
local table_wipe = table.wipe

-- unique marker for a slot whose value was removed, can never collide with a user value
local TOMBSTONE = setmetatable({}, { __tostring = function() return "<removed>" end })

-- Set class: ordered set of unique values
--
-- Values are appended to a flat array and located through an `index` lookup, so
-- membership is O(1) and iteration follows insertion order.
--
-- A removal blanks its slot with a tombstone rather than swapping the tail value down
-- into it, which is what keeps the order intact, and the array is compacted once the
-- dead slots outnumber the live ones, so a removal stays O(1) amortized.
local set = {}
set.__index = set

function set:__len()
    return self.size
end

function set:__tostring()
    return string.format("Set(%d)", self.size)
end

--- Drop the tombstones and pull the remaining values to the front
--- Moves values around, so do not call it while iterating the set
---@return table self
local function compact(self)
    local slots, size = self.slots, self.size
    if (slots == size) then return self end

    local data, index = self.data, self.index
    local target = 0

    for i = 1, slots do
        local value = data[i]

        if (value ~= TOMBSTONE) then
            target = target + 1

            if (target ~= i) then
                data[target] = value
                index[value] = target
            end
        end
    end

    for i = target + 1, slots do
        data[i] = nil
    end

    self.slots = size

    return self
end

set.compact = compact

function set.new(...)
    local self = setmetatable({
        data = {},  -- slot -> value
        index = {}, -- value -> slot
        size = 0,   -- live values
        slots = 0,  -- occupied slots, live values plus tombstones
        locks = 0,  -- running walks, compaction is held back while one is in flight
    }, set)

    for i = 1, select("#", ...) do
        self:add((select(i, ...)))
    end

    return self
end

--- Check if a value is in the set
---@param value any
---@return boolean
function set:has(value)
    return self.index[value] ~= nil
end

--- Check if the set holds no values
---@return boolean
function set:is_empty()
    return self.size == 0
end

--- Add a value, appended at the end, ignored if already present or nil
---@param value any
---@return table self
function set:add(value)
    if (value == nil) then return self end
    if (self.index[value]) then return self end

    local slots = self.slots + 1

    self.data[slots] = value
    self.index[value] = slots

    self.slots = slots
    self.size = self.size + 1

    return self
end

--- Remove every value from the set
---@return table self
function set:clear()
    if (self.locks == 0) then
        table_wipe(self.data)
        self.slots = 0
    else
        -- a walk is reading the array, blank the slots in place rather than pull them
        -- away from under it, the walk compacts them off on its way out
        local data = self.data

        for i = 1, self.slots do
            data[i] = TOMBSTONE
        end
    end

    table_wipe(self.index)
    self.size = 0

    return self
end

--- Delete a value, safe to call while walking the set
---@param value any
---@return boolean true if the value was present and was removed
function set:delete(value)
    local index = self.index
    local pos = index[value]
    if not (pos) then return false end

    local data = self.data
    local slots = self.slots
    local size = self.size - 1
    local unlocked = self.locks == 0

    index[value] = nil
    self.size = size

    if (unlocked and pos == slots) then
        -- value sits at the tail, drop it along with any tombstones it uncovers
        -- while a walk is running the array only ever grows, so this waits
        repeat
            data[slots] = nil
            slots = slots - 1
        until (slots == 0 or data[slots] ~= TOMBSTONE)

        self.slots = slots

        -- keep the dead slots from piling up
        if (slots > size * 2) then compact(self) end
    else
        data[pos] = TOMBSTONE

        if (unlocked and slots > size * 2) then compact(self) end
    end

    return true
end

--- Call a function for each value, in insertion order
--- Values may be added or deleted from within the callback, additions are walked too
---@param callback_fn fun(value: any)
---@return nil
function set:for_each(callback_fn)
    local data = self.data
    local locks = self.locks + 1
    local n = 0

    self.locks = locks

    -- walked in passes so the slot count stays out of the inner loop, a callback that
    -- adds values just leaves another pass to run, and the lock means nothing it
    -- removes can move a slot the walk has yet to reach
    repeat
        local last = self.slots

        for i = n + 1, last do
            local value = data[i]

            if (value ~= TOMBSTONE) then
                callback_fn(value)
            end
        end

        n = last
    until (self.slots <= n)

    locks = locks - 1
    self.locks = locks

    -- walking already cost a pass over the slots, so settle any dead ones while here
    if (locks == 0) then
        compact(self)
    end
end

--- Retrieve the value at an ordered position, negative counts from the end
---@param position number
---@return any
function set:at(position)
    local size = self.size

    if (position < 0) then
        position = size + position + 1
    end

    if (position < 1 or position > size) then return nil end

    local data = self.data

    -- no tombstones in the way, the position maps straight onto a slot
    if (self.slots == size) then
        return data[position]
    end

    local live = 0

    for i = 1, self.slots do
        local value = data[i]

        if (value ~= TOMBSTONE) then
            live = live + 1

            if (live == position) then
                return value
            end
        end
    end
end

--- Copy the values out as an array, in insertion order
---@param buffer table? table to fill instead of allocating one
---@return table
function set:array(buffer)
    local array = buffer or {}
    local data = self.data
    local live = 0

    for i = 1, self.slots do
        local value = data[i]

        if (value ~= TOMBSTONE) then
            live = live + 1
            array[live] = value
        end
    end

    return array
end

--- Stateful iterator over the values, in insertion order
--- Unlike for_each this does not hold back compaction, so do not delete while iterating
---@return fun(): any
function set:iterator()
    local data = self.data
    local n = 0

    return function()
        while (n < self.slots) do
            n = n + 1

            local value = data[n]
            if (value ~= TOMBSTONE) then
                return value
            end
        end
    end
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
