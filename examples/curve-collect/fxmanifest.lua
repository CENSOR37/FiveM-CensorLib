fx_version "cerulean"
game "gta5"
use_experimental_fxv2_oal "yes"

dependency "censorlib"
shared_script "@censorlib/imports.lua"
client_script "src/runtime/demo/client.lua"

files {
    "data/collect.lua",
    "src/modules/collect/client.lua",
}
