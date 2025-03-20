local keybind = {}
keybind.__index = keybind
keybind.__delegate_ids = {} -- temp

function keybind.new(name, desc, primary_key, primary_mapper, secondary_key, secondary_mapper)
    local self = {}
    self.name = name
    self.desc = desc
    self.default_key = primary_key
    self.default_mapper = primary_mapper or "keyboard"
    self.secondary_key = secondary_key
    self.secondary_mapper = secondary_mapper
    self.hash = joaat("+" .. self.name)
    self.disabled = false
    self.is_pressed = false
    self.delegate = {
        pressed = lib.delegate(),
        released = lib.delegate(),
    }

    RegisterCommand("+" .. self.name, function()
        if self.disabled or IsPauseMenuActive() then return end
        self.is_pressed = true

        self.delegate.pressed:broadcast(self)
    end, false)


    RegisterCommand("-" .. self.name, function()
        if self.disabled or IsPauseMenuActive() then return end
        self.is_pressed = false

        self.delegate.released:broadcast(self)
    end, false)

    RegisterKeyMapping("+" .. self.name, self.desc, self.default_mapper, self.default_key)

    if (self.secondary_key) then
        RegisterKeyMapping("~!+" .. self.name, self.desc, self.secondary_mapper or self.default_mapper, self.secondary_key)
    end

    lib.set_timeout(function()
        lib.emit("chat:removeSuggestion", ("/+%s"):format(self.name))
        lib.emit("chat:removeSuggestion", ("/-%s"):format(self.name))
    end, 500)

    return setmetatable(self, keybind)
end

function keybind:enable()
    self.disabled = false
end

function keybind:disable()
    self.disabled = true
end

function keybind:on_pressed(callback)
    return { "pressed", self.delegate.pressed:add(callback) }
end

function keybind:on_released(callback)
    return { "released", self.delegate.released:add(callback) }
end

function keybind:off(data)
    self.delegate[data[1]]:remove(data[2])
end

lib_module = setmetatable({
    new = keybind.new,
}, {
    __call = function(_, ...)
        return keybind.new(...)
    end,
})
