--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.
--- Adaptations from ox_lib are subject to its original license.
--- https://github.com/overextended/ox_lib/blob/main/imports/uuid/shared.lua - See original file for license details.

local table_create = table.create
local math_random = math.random
local table_unpack = table.unpack

local uuid_v7_pattern = table.concat({
    ("%02x"):rep(4),
    ("%02x"):rep(2),
    ("%02x"):rep(2),
    ("%02x"):rep(2),
    ("%02x"):rep(6),
}, "-")

local function get_timestamp()
    return (os and os.time() or GetCloudTimeAsInt()) * 1000
end

local uuid = {}

function uuid.v7()
    local timestamp = get_timestamp()
    local bytes = table_create(16, 0)

    for i = 1, 6 do
        bytes[i] = (timestamp >> (40 - (i - 1) * 8)) & 0xFF
    end

    for i = 7, 16 do
        bytes[i] = math_random(0, 255)
    end

    bytes[7] = (bytes[7] & 0x0F) | 0x70
    bytes[9] = (bytes[9] & 0x3F) | 0x80

    return uuid_v7_pattern:format(table_unpack(bytes))
end

function uuid.v7_validate(str)
    if type(str) ~= "string" or #str ~= 36 or not str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
        return false
    end

    local version = tonumber(str:sub(15, 15), 16)
    local variant = tonumber(str:sub(20, 20), 16)

    return version == 7 and (variant & 0x8) == 0x8
end

return uuid
