---@diagnostic disable-next-line: undefined-global
if (not package or not runtime) then
    load(LoadResourceFile("require", "init.lua"), "@@require")()
end

require "@censorlib.init"
