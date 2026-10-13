local module_warp = require "src.imports._module_warp.shared"
local class = require "src.imports.class.shared"

local state = class()

function state:constructor(in_value)
    self.private.value = in_value
    self.private.subscribers = {}
    self.value = in_value
end

function state:get()
    return self.private.value
end

function state:set(new_value)
    local prev_value = self.private.value
    local changed = (prev_value ~= new_value)

    if not (changed) then return end

    local old_value = prev_value

    self.private.value = new_value
    self.value = new_value

    for callback, _ in pairs(self.private.subscribers) do
        local success, err = pcall(callback, new_value, old_value)
        if not (success) then
            print(("state:subscribe callback error: %s"):format(err))
        end
    end
end

function state:watch(callback)
    self.private.subscribers[callback] = true

    return function()
        self:unwatch(callback)
    end
end

function state:unwatch(callback)
    self.private.subscribers[callback] = nil
end

-- compatibility alias
state.subscribe = state.watch
state.unsubscribe = state.unwatch

return module_warp.module_class_warp(state)
