local periodic = {}
periodic.__index = periodic

function periodic.new(tick_rate)
    tick_rate = lib.coalesce(tick_rate, 0)

    local self = {}
    self.handlers = {
        fn = {},
        list = {},
        length = 0,
    }
    self.b_reassign_table = false
    self.id = 10
    self.tick_rate = tick_rate
    self.interval = nil

    return setmetatable(self, periodic)
end

function periodic:add(fn_handler)
    lib.validate.type.assert(fn_handler, "function")

    self.id += 1
    self.handlers.fn[self.id] = fn_handler
    self.b_reassign_table = true

    if not (self.interval) then
        self.interval = lib.set_interval(function()
            local entries = self.handlers.list

            if (self.b_reassign_table) then
                table.wipe(entries)
                for _, value in pairs(self.handlers.fn) do
                    entries[#entries + 1] = value
                end
                self.handlers.length = #entries
                if (self.handlers.length <= 0) then
                    self.interval:destroy()
                    self.interval = nil
                end
            end

            for i = 1, self.handlers.length, 1 do
                entries[i]()
            end
        end, self.tick_rate)
    end

    return self.id
end

function periodic:remove(id)
    lib.validate.type.assert(id, "number")

    self.handlers.fn[id] = nil
    self.b_reassign_table = true
end

function periodic:clear()
    table.wipe(self.handlers.fn)
    self.b_reassign_table = true
end

function periodic:destroy()
    self:clear()
end

lib_module = setmetatable({
    new = periodic.new,
}, {
    __call = function(_, ...)
        return periodic.new(...)
    end,
})
