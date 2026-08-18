local _require = require
local noop = function() end

local loader = {}
local loaded = {}
local resource_name = GetCurrentResourceName()

local package = {
    path = "./?.lua;./?/init.lua",
    preload = {},
    loaded = setmetatable({}, {
        __index = loaded,
        __newindex = noop,
        __metatable = false,
    }),
}

---@param mod_name string
---@return string
---@return string
local function get_module_info(mod_name)
    local resource = mod_name:match("^@(.-)/.+") --[[@as string?]]

    if (resource) then
        return resource, mod_name:sub(#resource + 3)
    end

    local idx = 4 -- call stack depth (kept slightly lower than expected depth "just in case")

    while true do
        local src = debug.getinfo(idx, "S")?.source

        if not (src) then
            return resource_name, mod_name
        end

        resource = src:match("^@@([^/]+)/.+")

        if (resource) then
            return resource, mod_name
        end

        idx += 1
    end
end

local temp_data = {}

---@param name string
---@param path string
---@return string? filename
---@return string? errmsg
---@diagnostic disable-next-line: duplicate-set-field
function package.searchpath(name, path)
    local resource, mod_name = get_module_info(name:gsub("%.", "/"))
    local tried = {}

    for template in path:gmatch("[^;]+") do
        local file_name = template:gsub("^%./", ""):gsub("?", mod_name:gsub("%.", "/") or mod_name)
        local file = LoadResourceFile(resource, file_name)

        if file then
            temp_data[1] = file
            temp_data[2] = resource
            return file_name
        end

        tried[#tried + 1] = ("no file '@%s/%s'"):format(resource, file_name)
    end

    return nil, table.concat(tried, "\n\t")
end

---Attempts to load a module at the given path relative to the resource root directory.\
---Returns a function to load the module chunk, or a string containing all tested paths.
---@param mod_name string
---@param env? table
local function load_module(mod_name, env)
    local file_name, err = package.searchpath(mod_name, package.path)

    if (file_name) then
        local file = temp_data[1]
        local resource = temp_data[2]

        table.wipe(temp_data)
        return assert(load(file, ("@@%s/%s"):format(resource, file_name), "t", env or _ENV)), file_name
    end

    return nil, err or "unknown error"
end

---@alias PackageSearcher
---| fun(mod_name: string): function loader
---| fun(mod_name: string): nil, string errmsg

---@type PackageSearcher[]
package.searchers = {
    function(mod_name)
        local ok, result = pcall(_require, mod_name)

        if (ok) then return result end

        return ok, result
    end,
    function(mod_name)
        if (package.preload[mod_name] ~= nil) then
            return package.preload[mod_name]
        end

        return nil, ("no field package.preload['%s']"):format(mod_name)
    end,
    function(mod_name) return load_module(mod_name) end,
}

---@param file_path string
---@param env? table
---@return unknown
---Loads and runs a Lua file at the given path. Unlike require, the chunk is not cached for future use.
function loader.load(file_path, env)
    if (type(file_path) ~= "string") then
        error(("file path must be a string (received '%s')"):format(file_path), 2)
    end

    local result, err = load_module(file_path, env)

    if (result) then return result() end

    error(("file '%s' not found\n\t%s"):format(file_path, err))
end

---@param file_path string
---@return table
---Loads and decodes a json file at the given path.
function loader.load_json(file_path)
    if (type(file_path) ~= "string") then
        error(("file path must be a string (received '%s')"):format(file_path), 2)
    end

    local resource_src, mod_path = get_module_info(file_path:gsub("%.", "/"))
    local resource_file = LoadResourceFile(resource_src, ("%s.json"):format(mod_path))

    if (resource_file) then
        return json.decode(resource_file)
    end

    error(("json file '%s' not found\n\tno file '@%s/%s.json'"):format(file_path, resource_src, mod_path))
end

---Loads the given module, returns any value returned by the seacher (`true` when `nil`).\
---Passing `@resourceName.modName` loads a module from a remote resource.
---@param mod_name string
---@return unknown
function loader.require(mod_name)
    if (type(mod_name) ~= "string") then
        error(("module name must be a string (received '%s')"):format(mod_name), 3)
    end

    local module = loaded[mod_name]

    if (module == "__loading") then
        error(("^1circular-dependency occurred when loading module '%s'^0"):format(mod_name), 2)
    end

    if (module ~= nil) then return module end

    loaded[mod_name] = "__loading"

    local err = {}

    for i = 1, #package.searchers do
        local result, data = package.searchers[i](mod_name)

        if (result) then
            if (type(result) == "function") then result = result(mod_name, data) end
            loaded[mod_name] = result or result == nil

            return loaded[mod_name]
        end

        err[#err + 1] = data
    end

    error(("%s"):format(table.concat(err, "\n\t")))
end

return loader
