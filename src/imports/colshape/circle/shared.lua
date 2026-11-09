local lib = require "src.imports._lib.shared"
local common = require "src.imports.colshape._common.shared"
local class = require "src.imports.class.shared"
local draw_origin_dbg = common.draw_origin_dbg
local colshape = common.colshape_base_class
local numdeci = common.numdeci

local colshape_circle = class.extends(colshape)

function colshape_circle:constructor(position, radius)
    lib.validate.type.assert(position, "vector3", "vector4", "table")
    lib.validate.type.assert(radius, "number")

    local origin = vec(position.x, position.y, 0.0)

    self.super:constructor("circle", origin, position, radius)
    self.radius = numdeci(radius)
    self.position = vec(position.x, position.y)
end

function colshape_circle:native_args()
    return self.position.x, self.position.y, self.radius
end

function colshape_circle:is_position_inside(position)
    local point = vec(position.x, position.y)
    return #(point - self.position) <= self.radius
end

function colshape_circle:draw(r, g, b, a)
    if (lib.is_server) then return end

    local pos = self.position
    local rad = self.radius
    DrawMarker(1, pos.x, pos.y, -10000.0, 0, 0, 0, 0, 0, 0, rad * 2.0, rad * 2.0, 20000.0, r, g, b, a, false, false, 2, false, nil, nil, false)
end

function colshape_circle:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }

    self:draw(color.r, color.g, color.b, color.a)
end

return colshape_circle
