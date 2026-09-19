fx_version "cerulean"
use_experimental_fxv2_oal "yes"
lua54 "yes"
games { "gta5" }

--[[ Scripts. ]]
client_script "src/resource/startup-client.lua"
server_script "src/resource/startup-server.lua"

files {
    "init.lua",
    "imports.lua",
    "src/imports/**/client.lua",
    "src/imports/**/shared.lua",
    "src/modules/**/shared.lua",
    "src/modules/**/client.lua",
    "src/_lib/**/*shared*.lua",
    "src/_lib/**/*client*.lua",
    "src/resource/**/*shared*.lua",
    "src/resource/**/*server*.lua",
}
