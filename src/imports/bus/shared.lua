local module_warp = require "src.imports._module_warp.shared"

local bus = cslib.class()

function bus:constructor(opts)
    self.opts = opts or {}
    self.listeners = {}
end

function bus:on(event_name, callback)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(callback) == "function", "callback must be a function")

    local list = self.listeners[event_name]
    if (not list) then
        list = {}
        self.listeners[event_name] = list
    end

    list[#list + 1] = callback

    return function()
        self:off(event_name, callback)
    end
end

function bus:once(event_name, callback)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(callback) == "function", "callback must be a function")

    local unbind
    local function wrapper(...)
        if (unbind) then
            unbind()
            unbind = nil
        end
        callback(...)
    end

    unbind = self:on(event_name, wrapper)
    return unbind
end

function bus:off(event_name, callback)
    assert(type(event_name) == "string", "event_name must be a string")
    assert(type(callback) == "function", "callback must be a function")

    local list = self.listeners[event_name]
    if (not list) then
        return
    end

    local list_length = #list

    for i = list_length, 1, -1 do
        if (list[i] == callback) then
            table.remove(list, i)
            list_length -= 1
        end
    end

    if (list_length <= 0) then
        self.listeners[event_name] = nil
    end
end

function bus:emit(event_name, ...)
    assert(type(event_name) == "string", "event_name must be a string")

    local list = self.listeners[event_name]
    if (not list) then
        return
    end

    for i = 1, #list do
        local success, err = pcall(list[i], ...)
        if (not success) then
            print(("^1[Bus Error] Event '%s' callback failed: %s^0"):format(event_name, err))
        end
    end
end

function bus:clear(event_name)
    assert(type(event_name) == "string", "event_name must be a string")
    self.listeners[event_name] = nil
end

return module_warp.module_class_warp(bus)
