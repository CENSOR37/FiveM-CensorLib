--- Copyright (c) 2024-2026 CENSOR37. Licensed under the MIT License.
--- Adaptations from ox_lib are subject to its original license.
--- https://github.com/overextended/ox_lib/blob/main/imports/zones/shared.lua - See original file for license details.

local lib = require "src.imports._lib.shared"
local class = require "src.imports.class.shared"

local numdeci = function(value) return value + 0.0 end

local function draw_text_3d_dbg(text, point)
    local on_screen, x, y = World3dToScreen2d(point.x, point.y, point.z)
    if not (on_screen) then return end

    SetTextScale(0.0, 0.25)
    SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function draw_origin_dbg(colshape)
    local origin = colshape.origin
    local position = GetEntityCoords(PlayerPedId(), false)
    local dist = #(origin.xyz - position)
    DrawMarker(28, origin.x, origin.y, origin.z, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 255, 0, 0, 255, false, false, 2, false, nil, nil, false)
    draw_text_3d_dbg(("%.4f"):format(dist), origin)
end

local function colshape_classwarp(shapetype, class, ...)
    return setmetatable({
        new = function(...)
            return class:new(...)
        end,
        is_a = function(obj)
            return obj.shapetype == shapetype
        end,
    }, {
        __call = function(_, ...)
            return class:new(...)
        end,
    })
end

-- colshape
local colshape = class()

function colshape:constructor(in_shapetype, origin, ...)
    assert(origin, "origin is required")
    assert(in_shapetype, "shapetype is required")
    self.origin = origin
    self.shapetype = in_shapetype
    self.args = { ... }
end

function colshape:is_position_inside(position)
    return false
end

function colshape:is_point_inside(point)
    return self:is_position_inside(point)
end

function colshape:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)
end

return {
    colshape_base_class = colshape,
    colshape_classwarp = colshape_classwarp,
    draw_origin_dbg = draw_origin_dbg,
    numdeci = numdeci,
}
