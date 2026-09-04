assert(_VERSION:find("5.4"), "^1[ Please enable Lua 5.4 ]^0")

local lib_resource = "censorlib"
local context = IsDuplicityVersion() and "server" or "client"

local function preload_loader()
    local name = "_loader"
    local path = ("src/imports/%s/%s.lua"):format(name, "shared")
    local src = LoadResourceFile(lib_resource, path)

    local chunk, err = load(src, ("@@%s/src/imports/%s/%s.lua"):format(lib_resource, name, context))
    assert(chunk and not err, ("\n^1Error importing module (%s): %s^0"):format(path, err))

    local ok, result = pcall(chunk, lib_resource)
    assert(ok and result, ("\n^1Error importing module (%s): %s^0"):format(path, result))

    return result
end

local loader = preload_loader()
local lib = loader.require(("src.imports._lib.shared"):format(lib_resource))
lib._loader = loader

local function load_module(tbl, name)
    local ok, module = pcall(lib._loader.require, ("@%s.src.imports.%s.%s"):format(lib_resource, name, context))
    if (not ok) then
        ok, module = pcall(lib._loader.require, ("@%s.src.imports.%s.shared"):format(lib_resource, name))
    end

    assert(ok and module, ("\n^1Error importing module (%s): %s^0"):format(name, module))
    rawset(tbl, name, module)

    return module
end

setmetatable(lib, { __index = load_module, __call = load_module })

rawset(_ENV, "cslib", lib)

-- Note: this working fine even with other loader, go read "src/imports/_loader/shared.lua" for more details
require = lib._loader.require

-----------------------------------------------------------------------------------------------
-- API: Common functions
-----------------------------------------------------------------------------------------------

local is_server = IsDuplicityVersion()

lib.is_server = is_server
lib.is_client = not is_server
lib.service = is_server and "server" or "client"
lib.service_inversed = is_server and "client" or "server"

lib.set_interval = function(handler, delay)
    return lib.timer.new(handler, delay, true)
end

lib.set_timeout = function(handler, delay)
    return lib.timer.new(handler, delay, false)
end

lib.on_tick = function(handler)
    return lib.timer.new(handler, 0, true)
end

lib.on_next_tick = function(handler)
    return lib.timer.new(handler, 0, false)
end

lib.clear_interval = function(timer)
    if (timer ~= nil) then
        timer:destroy()
    end
end

lib.clear_timer = function(timer)
    if (timer ~= nil) then
        timer:destroy()
    end
end

for key, value in pairs(lib._event) do
    if (value ~= nil) then
        lib[key] = value
    end
end

lib.uuid = lib.random.uuid

-- common functions
lib.coalesce = lib.common.coalesce
lib.require = lib._loader.require
lib.load = lib._loader.load
lib.load_json = lib._loader.load_json
