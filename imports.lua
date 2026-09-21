local init_src = LoadResourceFile("censorlib", "init.lua")
local init_chunk = load(init_src, "@censorlib/init.lua")

if (init_chunk) then
    pcall(init_chunk)
end
