--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.

local class = require "src.imports.class.shared"
local current_resourcename = GetCurrentResourceName()
local batcher = class()
local instances = {}

local current_batch_id = 10
local function next_batch_id()
    current_batch_id += 1
    return current_batch_id
end

local timestamp = GetGameTimer

cslib.on("onResourceStop", function(resource_name)
    if (resource_name ~= current_resourcename) then return end
    -- Assigning nil to existing keys during traversal is safe in Lua.
    for instance in pairs(instances) do
        instance:destroy()
    end
end)

---@class BatcherOptions
---@field max_size? number        Flush when the queue reaches this many actions (default 10).
---@field max_wait_ms? number     Flush this long after the first queued action (default 2000).
---@field pending_ttl_ms? number  Drop un-acked batches older than this (default 60000).

---@param opts? BatcherOptions
function batcher:constructor(opts)
    opts = opts or {}

    if (opts.max_size ~= nil) then cslib.validate.type.assert(opts.max_size, "number") end
    if (opts.max_wait_ms ~= nil) then cslib.validate.type.assert(opts.max_wait_ms, "number") end
    if (opts.pending_ttl_ms ~= nil) then cslib.validate.type.assert(opts.pending_ttl_ms, "number") end

    -- Public config (read-only by convention)
    self.max_size           = math.max(1, opts.max_size or 10)
    self.max_wait_ms        = opts.max_wait_ms or 2000
    self.pending_ttl_ms     = opts.pending_ttl_ms or 60000

    -- Private state: do not touch from outside, use the methods.
    self._queue             = {}
    self._queue_len         = 0
    self._timer             = nil
    self._delegate          = cslib.delegate()
    self._destroyed         = false
    self._pending_batches   = {}
    self._pending_timestamp = {}

    instances[self]         = true

    return setmetatable(self, batcher)
end

function batcher:destroy()
    if (self._destroyed) then return end

    self:flush()
    self:_clear_timer()
    self._destroyed = true
    self._pending_batches = {}
    self._pending_timestamp = {}
    instances[self] = nil
end

function batcher:_clear_timer()
    local timer = self._timer
    self._timer = nil
    if (timer) then timer:destroy() end
end

function batcher:_sweep_pending()
    local now = timestamp()
    local ttl = self.pending_ttl_ms
    for batch_id, created_at in pairs(self._pending_timestamp) do
        if (now - created_at > ttl) then
            cslib.print.verbose(("BATCHER DROPPED STALE BATCH %d"):format(batch_id))
            self._pending_batches[batch_id] = nil
            self._pending_timestamp[batch_id] = nil
        end
    end
end

---@return boolean accepted
function batcher:enqueue(action)
    if (self._destroyed or action == nil) then return false end

    self._queue_len += 1
    self._queue[self._queue_len] = action

    if (self._queue_len >= self.max_size) then
        cslib.print.verbose("BATCHER FLUSH BY SIZE")
        self:flush()
        return true
    end

    if not (self._timer) then
        self._timer = cslib.set_timeout(function()
            -- Timer already fired: drop the reference so flush() won't destroy it.
            self._timer = nil
            cslib.print.verbose("BATCHER FLUSH BY TIMEOUT")
            self:flush()
        end, self.max_wait_ms)
    end

    return true
end

---@param actions table
function batcher:enqueue_many(actions)
    cslib.validate.type.assert(actions, "table")
    for i = 1, #actions do
        self:enqueue(actions[i])
    end
end

---@return number? batch_id nil if there was nothing to send
function batcher:flush()
    -- Always clear the timer, even if the queue is empty.
    self:_clear_timer()

    if (self._queue_len <= 0) then
        return nil
    end

    local batch = self._queue
    local batch_id = next_batch_id()

    self._queue = {}
    self._queue_len = 0

    if not (self._destroyed) then
        self:_sweep_pending()
        self._pending_batches[batch_id] = batch
        self._pending_timestamp[batch_id] = timestamp()
    end

    self._delegate:broadcast(batch_id, batch)
    return batch_id
end

---Re-sends a batch that hasn't been acknowledged yet.
---@param batch_id number
---@return boolean found
function batcher:resend(batch_id)
    local batch = self._pending_batches[batch_id]
    if (batch) then
        self._delegate:broadcast(batch_id, batch)
        return true
    end
    return false
end

---Acknowledges a batch so it's no longer kept for resending.
---@param batch_id number
function batcher:ack(batch_id)
    self._pending_batches[batch_id] = nil
    self._pending_timestamp[batch_id] = nil
end

---@return number
function batcher:size()
    return self._queue_len
end

---@return boolean
function batcher:is_destroyed()
    return self._destroyed
end

---@param listener fun(batch_id: number, batch: table)
function batcher:on_batch(listener)
    cslib.validate.type.assert(listener, "function")
    self._delegate:add(listener)
end

return batcher
