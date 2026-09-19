local next = next
local table = table
local table_insert = table.insert
local table_remove = table.remove

local spatial_grid = cslib.class()

---@param bound_min vector2|table {x, y}
---@param bound_max vector2|table {x, y}
---@param cell_size vector2|table {x, y} this is the size of each cell in world units
function spatial_grid:constructor(bound_min, bound_max, cell_size)
    assert(bound_min.x < bound_max.x, ("[Spatial Grid] invalid bound_min.x (%s) >= bound_max.x (%s)"):format(tostring(bound_min.x), tostring(bound_max.x)))
    assert(bound_min.y < bound_max.y, ("[Spatial Grid] invalid bound_min.y (%s) >= bound_max.y (%s)"):format(tostring(bound_min.y), tostring(bound_max.y)))
    assert(cell_size.x > 0, ("[Spatial Grid] invalid cell_size.x (%s), must be > 0"):format(tostring(cell_size.x)))
    assert(cell_size.y > 0, ("[Spatial Grid] invalid cell_size.y (%s), must be > 0"):format(tostring(cell_size.y)))

    self.min_x = bound_min.x
    self.min_y = bound_min.y
    self.max_x = bound_max.x
    self.max_y = bound_max.y

    self.cell_size_x = cell_size.x
    self.cell_size_y = cell_size.y

    self.col = (self.max_x - self.min_x) // self.cell_size_x
    self.row = (self.max_y - self.min_y) // self.cell_size_y

    self.cells = {}
    self.query_id = 0

    self.insert_id = 0
    self._free_handles = {} -- recycled IDs, to keep it array like

    self.storage = {
        _query_id = {},
        _cell_min_x = {},
        _cell_max_x = {},
        _cell_min_y = {},
        _cell_max_y = {},
    }
end

-- NOW THIS FUNCTION IS BEING INLINED MANUALLY FOR PERFORMANCE
-- KEEP FOR DEBUGGING PURPOSES
-- [INTERNAL] Generate a unique key for cell indices
-- Packs two 32-bit ints into one 64-bit int.
-- Range: +/- 2,147,483,647 cells on each axis.
function spatial_grid:_grid_key(x, y)
    return (y << 32) | (x & 0xFFFFFFFF)
end

-- NOW THIS FUNCTION IS BEING INLINED MANUALLY FOR PERFORMANCE
-- KEEP FOR DEBUGGING PURPOSES
-- [INTERNAL] Convert world scalar x,y to cell indices
function spatial_grid:_get_cell_index(pos_x, pos_y)
    local cell_x = (pos_x - self.min_x) // self.cell_size_x
    local cell_y = (pos_y - self.min_y) // self.cell_size_y

    return cell_x, cell_y
end

-- [INTERNAL] Calculate the range of cells an object touches
function spatial_grid:_get_cell_bounds(pos_x, pos_y, size_x, size_y)
    local min_x = (pos_x - size_x - self.min_x) // self.cell_size_x
    local min_y = (pos_y - size_y - self.min_y) // self.cell_size_y
    local max_x = (pos_x + size_x - self.min_x) // self.cell_size_x
    local max_y = (pos_y + size_y - self.min_y) // self.cell_size_y

    return min_x, min_y, max_x, max_y
end

-- [INTERNAL] Add to cells using indices
function spatial_grid:_add_to_cells(handle, min_x, min_y, max_x, max_y)
    local grid = self.cells

    for y = min_y, max_y do
        local y_shift = y << 32
        for x = min_x, max_x do
            local key = y_shift | (x & 0xFFFFFFFF)
            local cell = grid[key]
            if not (cell) then
                cell = {}
                grid[key] = cell
            end
            cell[handle] = true
        end
    end

    local store = self.storage
    store._cell_min_x[handle] = min_x
    store._cell_min_y[handle] = min_y
    store._cell_max_x[handle] = max_x
    store._cell_max_y[handle] = max_y
end

-- [INTERNAL] Remove from cells using indices
function spatial_grid:_remove_from_cells(handle, min_x, min_y, max_x, max_y)
    local grid = self.cells

    for y = min_y, max_y do
        local y_shift = y << 32
        for x = min_x, max_x do
            local key = y_shift | (x & 0xFFFFFFFF)
            local cell = grid[key]
            if (cell) then
                cell[handle] = nil

                -- clean up empty cells, this not only saves memory but also speeds up queries
                if (next(cell) == nil) then
                    grid[key] = nil
                end
            end
        end
    end
end

--- Add an object to the grid.
---@param position vector2  World Position
---@param size     vector2  World Size/Radius
---@return number handle  A handle to reference the object in future operations
function spatial_grid:insert(position, size)
    local handle = table_remove(self._free_handles)
    if not (handle) then
        self.insert_id = self.insert_id + 1
        handle = self.insert_id
    end
    local min_x, min_y, max_x, max_y = self:_get_cell_bounds(position.x, position.y, size.x, size.y)
    self:_add_to_cells(handle, min_x, min_y, max_x, max_y)
    return handle
end

--- Remove an object from the grid.
---@param handle   number    The handle returned by insert()
function spatial_grid:remove(handle)
    local store = self.storage
    local min_x = store._cell_min_x[handle]

    if not (min_x) then return end

    local min_y = store._cell_min_y[handle]
    local max_x = store._cell_max_x[handle]
    local max_y = store._cell_max_y[handle]

    self:_remove_from_cells(handle, min_x, min_y, max_x, max_y)

    -- clear stored cell bounds, prevent it from further use such as update()
    store._cell_min_x[handle] = nil
    store._cell_min_y[handle] = nil
    store._cell_max_x[handle] = nil
    store._cell_max_y[handle] = nil
    store._query_id[handle] = nil

    table_insert(self._free_handles, handle)
end

--- Update an object's position in the grid.
--- @param handle   number    The handle returned by insert()
--- @param position vector2  New World Position
--- @param size     vector2  New World Size/Radius
function spatial_grid:update(handle, position, size)
    local store = self.storage
    local old_min_x = store._cell_min_x[handle]

    if not (old_min_x) then return end

    local new_min_x, new_min_y, new_max_x, new_max_y = self:_get_cell_bounds(position.x, position.y, size.x, size.y)

    if (new_min_x == old_min_x) and
        (new_min_y == store._cell_min_y[handle]) and
        (new_max_x == store._cell_max_x[handle]) and
        (new_max_y == store._cell_max_y[handle]) then
        return
    end

    local old_max_x = store._cell_max_x[handle]
    local old_min_y = store._cell_min_y[handle]
    local old_max_y = store._cell_max_y[handle]

    self:_remove_from_cells(handle, old_min_x, old_min_y, old_max_x, old_max_y)

    self:_add_to_cells(handle, new_min_x, new_min_y, new_max_x, new_max_y)
end

--- Query the grid for objects overlapping a given area.
--- @param position vector2  World Position
--- @param size     vector2  World Size/Radius
--- @param buffer   table    (optional) A table to store results in
--- @return table buffer  The table containing the results
--- @return number count  The number of results found
function spatial_grid:query(position, size, buffer)
    local min_x, min_y, max_x, max_y = self:_get_cell_bounds(position.x, position.y, size.x, size.y)

    self.query_id = self.query_id + 1
    local current_query_id = self.query_id

    buffer = buffer or {}
    local count = 0

    local grid = self.cells

    local q_ids = self.storage._query_id

    for y = min_y, max_y do
        local y_shift = y << 32
        for x = min_x, max_x do
            local key = y_shift | (x & 0xFFFFFFFF)
            local cell = grid[key]
            if (cell) then
                for handle in next, cell do
                    if (q_ids[handle] ~= current_query_id) then
                        q_ids[handle] = current_query_id
                        count = count + 1
                        buffer[count] = handle
                    end
                end
            end
        end
    end

    return buffer, count
end

return spatial_grid
