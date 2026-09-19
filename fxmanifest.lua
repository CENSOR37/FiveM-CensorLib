fx_version "cerulean"
use_experimental_fxv2_oal "yes"
lua54 "yes"
games { "gta5" }

--[[ Scripts. ]]
server_scripts {
    "src/resource/**/*shared*.lua",
    "src/resource/**/*server*.lua",
}

client_scripts {
    "src/resource/**/*shared*.lua",
    "src/resource/**/*client*.lua",
}

files {
    "init.lua",
    "imports.lua",
    "src/imports/**/client.lua",
    "src/imports/**/shared.lua",
    "src/modules/**/shared.lua",
    "src/modules/**/client.lua",
}
