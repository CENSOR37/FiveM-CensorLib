local randset = {}
randset.__index = randset

function randset.new(...)
    local self = setmetatable({}, randset)
    self.pool = {}
    self.key = 10
    self.cumulative = 0
    return self
end

function randset:calculate_cumulative()
    self.cumulative = 0

    for _, item in pairs(self.pool) do
        self.cumulative = self.cumulative + item.chance
        item.chance_end = self.cumulative
    end
end

function randset:add_item(chance, data)
    lib.validate.type.assert(chance, "number")

    if not (data) then
        error("data is required")
    end

    self.key = self.key + 1
    self.pool[self.key] = { chance = chance, data = data }

    self:calculate_cumulative()

    return self.key
end

function randset:remove_item(key)
    lib.validate.type.assert(key, "number")

    self.pool[key] = nil
    self:calculate_cumulative()
end

function randset:random()
    if (self.cumulative == 0) then return nil end

    local random = math.random() * self.cumulative

    for _, value in pairs(self.pool) do
        if (random <= value.chance_end) then
            return value.data
        end
    end
end

lib_module.chance_pool = setmetatable({ new = randset.new }, {
    __call = function(t, ...)
        return randset.new(...)
    end,
})
