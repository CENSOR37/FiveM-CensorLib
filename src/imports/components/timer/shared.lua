local wait = Wait
local citizen_create_thread_now = Citizen.CreateThreadNow

local timer = {}
timer.__index = timer
function timer.new(handler, delay, is_loop)
    local self = {}

    self.delay = delay or 0
    self.is_destroyed = false
    self.is_loop = (is_loop ~= nil) and is_loop or false
    self.fn_handler = handler

    self.handler = function()
        wait(self.delay)
        if (self.is_destroyed) then return end
        self.fn_handler()
    end

    citizen_create_thread_now(function(ref)
        self.id = ref
        if (self.is_loop) then
            while not (self.is_destroyed) do
                self.handler()
            end
        else
            self.handler()
        end
    end)

    return setmetatable(self, timer)
end

function timer:destroy()
    if (self.is_destroyed) then return end
    self.is_destroyed = true
end

lib_module = setmetatable({
    new = timer.new,
}, {
    __call = function(_, ...)
        return timer.new(...)
    end,
})
