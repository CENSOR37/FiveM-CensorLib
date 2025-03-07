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

    print(("[^2%s^7] print level set to ^5%s^7"):format(lib.resource.name, new_convar))
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

lib_module.error = function(...) lib_print(1, ...) end
lib_module.warn = function(...) lib_print(2, ...) end
lib_module.info = function(...) lib_print(3, ...) end
lib_module.verbose = function(...) lib_print(4, ...) end
lib_module.debug = function(...) lib_print(5, ...) end
