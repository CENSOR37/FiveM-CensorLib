--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.
--- Adaptations from ox_lib are subject to its original license.
--- https://github.com/overextended/ox/blob/main/require.lua - See original file for license details.
--- See https://github.com/overextended/cfxlua-require

local loader = {}

---@param file_path string
---@param env? table
---@return unknown
---Loads and runs a Lua file at the given path. Unlike require, the chunk is not cached for future use.
function loader.load(file_path, env)
    return loadfile(file_path, "t", env)()
end

loader.load_json = json.load
loader.require = require

return loader
