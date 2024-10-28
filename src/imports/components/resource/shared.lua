local native = {
    get_current_resource_name = GetCurrentResourceName,
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
            return lib.net.callback.register(self:prefix(eventname), ...)
        end,
        await = function(eventname, ...)
            return lib.net.callback.await(self:prefix(eventname), ...)
        end,
    }, {
        __call = function(t, eventname, ...)
            return lib.net.callback(self:prefix(eventname), ...)
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

if (lib.is_server) then
    function resource:emit_client(eventname, client, ...)
        return lib.emit_client(self:prefix(eventname), client, ...)
    end

    function resource:emit_all_clients(eventname, ...)
        return lib.emit_all_clients(self:prefix(eventname), ...)
    end

    function resource:on_client(eventname, callback)
        return lib.on_client(self:prefix(eventname), callback)
    end

    function resource:once_client(eventname, callback)
        return lib.once_client(self:prefix(eventname), callback)
    end
else
    function resource:emit_server(eventname, ...)
        return lib.emit_server(self:prefix(eventname), ...)
    end

    function resource:on_server(eventname, callback)
        return lib.on_server(self:prefix(eventname), callback)
    end

    function resource:once_server(eventname, callback)
        return lib.once_server(self:prefix(eventname), callback)
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

cslib_component = setmetatable({
    get = function(resource)
        return resource.new(resource)
    end,
}, {
    __index = function(t, field)
        return instances[resource_name][field]
    end,
})
