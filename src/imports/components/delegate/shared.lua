local table_wipe = table.wipe

local delegate = {}
delegate.__index = delegate

function delegate.new()
    local self = setmetatable({}, delegate)
    self.listener_id = 10
    self.listeners = {}
    self._locked = false
    self._pending_unbinds = nil
    self._unsafe = true -- wip: todo ??

    return self
end

function delegate:size()
    return #self.listeners
end

function delegate:bind(listener, once)
    assert(type(listener) == "function", ("delegate:bind expects a function, got %s"):format(type(listener)))

    self.listener_id = self.listener_id + 1
    local listener_info = { id = self.listener_id, listener = listener, once = once or false }
    self.listeners[#self.listeners + 1] = listener_info

    return listener_info.id
end

function delegate:bind_once(listener)
    return self:bind(listener, true)
end

function delegate:unbind(id)
    if (self._locked) then
        self._pending_unbinds = self._pending_unbinds or {}
        self._pending_unbinds[id] = true
        return
    end

    for i = 1, #self.listeners, 1 do
        local listener_info = self.listeners[i]
        if (listener_info.id == id) then
            table.remove(self.listeners, i)
            break
        end
    end
end

delegate.add = delegate.bind
delegate.remove = delegate.unbind

function delegate:is_bound(id)
    for i = 1, #self.listeners, 1 do
        if (self.listeners[i].id == id) then
            return true
        end
    end

    return false
end

local function run_unsafe_broadcast(listeners, n, ...)
    local once_ids = nil

    for i = 1, n, 1 do
        local listener_info = listeners[i]
        listener_info.listener(...)

        if (listener_info.once) then
            once_ids = once_ids or {}
            once_ids[#once_ids + 1] = listener_info.id
        end
    end

    return once_ids
end

function delegate:broadcast(...)
    local listeners = self.listeners
    local n = #listeners
    if (n <= 0) then return end

    self._locked = true

    local once_ids = nil

    if (self._unsafe) then
        local ok, result_or_err = pcall(run_unsafe_broadcast, listeners, n, ...)

        if (ok) then
            once_ids = result_or_err
        end

        self._locked = false
        self:_flush_unbinds(once_ids)

        if not (ok) then
            error(result_or_err, 0)
        end

        return
    end

    for i = 1, n, 1 do
        local listener_info = listeners[i]
        local ok, err = xpcall(listener_info.listener, debug.traceback, ...)
        if not (ok) then
            lib.print.error(("^1[delegate] listener error: %s^7"):format(tostring(err)))
        end

        if (listener_info.once) then
            once_ids = once_ids or {}
            once_ids[#once_ids + 1] = listener_info.id
        end
    end

    self._locked = false
    self:_flush_unbinds(once_ids)
end

function delegate:_flush_unbinds(once_ids)
    if (once_ids) then
        for i = 1, #once_ids, 1 do
            self:unbind(once_ids[i])
        end
    end

    if (self._pending_unbinds) then
        local pending = self._pending_unbinds
        self._pending_unbinds = nil

        for id in pairs(pending) do
            self:unbind(id)
        end
    end
end

function delegate:empty()
    self.listeners = table_wipe(self.listeners)
    self._pending_unbinds = nil
end

lib_module = setmetatable({ new = delegate.new }, { __call = function(_, ...) return delegate.new(...) end })
