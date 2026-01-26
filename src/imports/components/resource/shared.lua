local native = {
    get_current_resource_name = GetCurrentResourceName,
    get_resource_state = GetResourceState,
}

local eventnames = {
    on_resource_start = "onResourceStart",
    on_resource_stop = "onResourceStop",
}

local resource = {}
resource.__index = resource

function resource.new(resource_name)
    local self = setmetatable({}, resource)
    self.name = resource_name
    self.callback = setmetatable({
        register = function(eventname, ...)
            return lib.callback.register(self:prefix(eventname), ...)
        end,
    }, {
        __call = function(_, eventname, ...)
            return lib.callback(self:prefix(eventname), ...)
        end,
    })

    return setmetatable(self, {
        __index = function(t, field)
            return setmetatable({}, {
                __call = function(_, arg1, ...)
                    if (arg1 == self) then
                        return resource[field](arg1, ...)
                    end

                    return resource[field](self, arg1, ...)
                end,
            })
        end,
    })
end

function resource:prefix(...)
    local args = { ... }
    table.insert(args, 1, self.name)
    return table.concat(args, ":")
end

function resource:on(eventname, callback)
    return lib.on(self:prefix(eventname), callback)
end

function resource:once(eventname, callback)
    return lib.once(self:prefix(eventname), callback)
end

function resource:emit(eventname, ...)
    return lib.emit(self:prefix(eventname), ...)
end

for key, value in pairs(lib._event) do
    if (key ~= "off" and value ~= nil) then
        resource[key] = function(self, eventname, ...)
            return value(self:prefix(eventname), ...)
        end
    end
end

function resource:on_start(callback)
    return lib.on(eventnames.on_resource_start, function(starting_resource)
        if (self.name ~= starting_resource) then return end
        callback()
    end)
end

function resource:on_stop(callback)
    return lib.on(eventnames.on_resource_stop, function(stopping_resource)
        if (self.name ~= stopping_resource) then return end
        callback()
    end)
end

local instances = {}
local resource_name = native.get_current_resource_name()
instances[resource_name] = resource.new(resource_name)
local self_instance = instances[resource_name]

lib_module = setmetatable({}, {
    __index = function(t, field)
        local method = self_instance[field]
        if (method) then return method end

        if (native.get_resource_state(field) == "started") then
            local instance = instances[field] or resource.new(field)
            instances[field] = instance
            return instance
        end

        error(("Cannot find a method or resource named \"%s\""):format(field))
    end,
})
