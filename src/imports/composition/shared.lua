local lib = require "src.imports._lib.shared"
local class = lib.class

local composition = {}
composition.__index = composition

local function traceback(err)
    return debug.traceback(tostring(err), 2)
end

local function validate_selector(selector)
    assert(type(selector) == "string" or type(selector) == "table", "component selector must be a name or cslib.class")
end

local function find_entry(self, selector)
    validate_selector(selector)
    if (type(selector) == "string") then return self._entries[selector] end

    local found
    for i = 1, #self._order do
        local entry = self._order[i]
        if (entry.class == selector) then
            assert(not found, "multiple components match this class; use a component name")
            found = entry
        end
    end
    return found
end

local function unregister(self, entry)
    self._entries[entry.name] = nil
    for i = #self._order, 1, -1 do
        if (self._order[i] == entry) then
            table.remove(self._order, i)
            break
        end
    end
end

local function destroy_entry(entry, owner)
    -- Actual ownership does not depend on the component's public owner field.
    rawset(entry.instance, "owner", owner)
    local ok, err = xpcall(entry.instance.destroy, traceback, entry.instance)
    rawset(entry.instance, "owner", nil)
    return ok, err
end

function composition.new(owner)
    lib.validate.type.assert(owner, "table")
    return setmetatable({
        _owner = owner,
        _entries = {},
        _order = {},
        _pending = {},
        _closed = false,
    }, composition)
end

function composition:add(name, component_class, ...)
    assert(not self._closed and not self._owner_destroyed, "cannot add components to a destroyed composition")
    assert(type(name) == "string" and name ~= "", "component name must be a non-empty string")
    assert(not self._entries[name] and not self._pending[name], ("component name already in use: '%s'"):format(name))
    assert(type(component_class) == "table" and type(component_class.new) == "function", "component must be a class")
    local destroy = component_class.destroy
    assert(type(destroy) == "function", "component class must provide destroy()")

    local owned_class = class.extends(component_class)
    assert(component_class.new == owned_class.new, "composition does not support classes with a custom new method")

    local partial
    function owned_class:constructor(owner, ...)
        partial = self
        self.owner = owner
        self:super(...)
    end

    local owner = self._owner
    self._pending[name] = true
    local ok, instance = xpcall(owned_class.new, traceback, owned_class, owner, ...)
    self._pending[name] = nil
    if (not ok and partial) then rawset(partial, "owner", nil) end
    partial = nil
    if (not ok) then error(instance, 0) end

    local entry = { name = name, class = component_class, instance = instance }

    -- A constructor may yield or destroy its owner before returning.
    if (self._closed) then
        local cleaned, err = destroy_entry(entry, owner)
        local message = "composition was destroyed during component construction"
        if (not cleaned) then message = message .. "\n" .. err end
        error(message, 2)
    end

    self._entries[name] = entry
    self._order[#self._order + 1] = entry
    return instance
end

function composition:get(selector)
    local entry = find_entry(self, selector)
    return entry and entry.instance or nil
end

function composition:get_all(component_class)
    lib.validate.type.assert(component_class, "table")
    local result = {}
    for i = 1, #self._order do
        local entry = self._order[i]
        if (entry.class == component_class) then result[#result + 1] = entry.instance end
    end
    return result
end

function composition:has(selector)
    validate_selector(selector)
    if (type(selector) == "string") then return self._entries[selector] ~= nil end
    for i = 1, #self._order do
        if (self._order[i].class == selector) then return true end
    end
    return false
end

function composition:remove(selector)
    local entry = find_entry(self, selector)
    if (not entry) then return false end

    unregister(self, entry)
    self._pending[entry.name] = true
    local ok, err = destroy_entry(entry, self._owner)
    self._pending[entry.name] = nil
    if (not ok) then error(err, 0) end
    return true
end

function composition:destroy()
    if (self._closed) then return end
    self._closed = true

    local errors = {}
    while (#self._order > 0) do
        local entry = self._order[#self._order]
        unregister(self, entry)
        local ok, err = destroy_entry(entry, self._owner)
        if (not ok) then errors[#errors + 1] = ("component '%s': %s"):format(entry.name, err) end
    end
    self._owner = nil
    if (#errors > 0) then error(table.concat(errors, "\n"), 0) end
end

local containers = setmetatable({}, { __mode = "k" })

local function get_container(owner)
    local container = containers[owner]
    if (not container) then
        container = composition.new(owner)
        containers[owner] = container

        -- Wrap the instance so class methods, private access, and super stay intact.
        local destroy = owner.destroy
        rawset(owner, "destroy", function(self, ...)
            if (container._owner_destroyed) then return end
            container._owner_destroyed = true

            local result = table.pack(xpcall(destroy, traceback, self, ...))
            local success, err = xpcall(container.destroy, traceback, container)
            if (not result[1]) then
                if (not success) then result[2] = result[2] .. "\n" .. err end
                error(result[2], 0)
            end
            if (not success) then error(err, 0) end
            return table.unpack(result, 2, result.n)
        end)
    end
    return container
end

local composition_methods = {}

function composition_methods:add_component(name, component_class, ...)
    return get_container(self):add(name, component_class, ...)
end

function composition_methods:get_component(selector)
    return get_container(self):get(selector)
end

function composition_methods:get_components(component_class)
    return get_container(self):get_all(component_class)
end

function composition_methods:has_component(selector)
    return get_container(self):has(selector)
end

function composition_methods:remove_component(selector)
    return get_container(self):remove(selector)
end

function composition_methods:destroy_components()
    get_container(self):destroy()
end

-- aliases
composition_methods.find_component = composition_methods.get_component
composition_methods.find_components = composition_methods.get_components

local function apply(target)
    lib.validate.type.assert(target, "table")
    assert(target.destroy == nil or type(target.destroy) == "function", "composition destroy must be a function")

    for name, method in pairs(composition_methods) do
        assert(target[name] == nil or target[name] == method, ("composition method conflict: '%s'"):format(name))
    end

    for name, method in pairs(composition_methods) do
        if (target[name] == nil) then target[name] = method end
    end
    if (target.destroy == nil) then target.destroy = composition_methods.destroy_components end

    return target
end

return { apply = apply }
