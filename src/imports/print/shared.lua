local lib = require "src.imports._lib.shared"

-- a huge courtesy to overextended team.

local prefix_levels = {
    error = 1,
    warn = 2,
    info = 3,
    verbose = 4,
    debug = 5,
}

local prefixes_str = {
    "^1[ERROR]",
    "^3[WARN]",
    "^7[INFO]",
    "^4[VERBOSE]",
    "^6[DEBUG]",
}

local function handle_json_exception(reason, value)
    if type(value) == "function" then return tostring(value) end
    return reason
end
local json_opts = { sort_keys = true, indent = true, exception = handle_json_exception }
local print_level = 3
local convar_key = ("%s:print_level"):format(lib.resource.name)

local function make_convar_dirty()
    local new_convar = GetConvar(convar_key, "info")
    print_level = prefix_levels[new_convar] or 3
end
make_convar_dirty()
AddConvarChangeListener(convar_key, make_convar_dirty)

local template = ("^5[%s] %%s %%s^7"):format(lib.resource.name)
local function lib_print(in_level, ...)
    if (in_level > print_level) then return end

    local in_args = { ... }

    for i = 1, #in_args do
        local arg = in_args[i]
        in_args[i] = type(arg) == "table" and json.encode(arg, json_opts) or tostring(arg)
    end

    print(template:format(prefixes_str[in_level], table.concat(in_args, "\t")))
end

return {
    error = function(...) lib_print(1, ...) end,
    warn = function(...) lib_print(2, ...) end,
    info = function(...) lib_print(3, ...) end,
    verbose = function(...) lib_print(4, ...) end,
    debug = function(...) lib_print(5, ...) end,
}
