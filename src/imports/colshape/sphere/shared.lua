local lib = require "src.imports._lib.shared"
local common = require "src.imports.colshape._common.shared"
local class = require "src.imports.class.shared"
local draw_origin_dbg = common.draw_origin_dbg
local colshape = common.colshape_base_class
local numdeci = common.numdeci

-- colshape_sphere
local colshape_sphere = class.extends(colshape)

function colshape_sphere:constructor(position, radius)
    lib.validate.type.assert(position, "vector3", "vector4", "table")
    lib.validate.type.assert(radius, "number")

    local origin = vec(position.x, position.y, position.z)

    self.super:constructor("sphere", origin, position, radius)
    self.radius = radius
    self.position = vec(position.x, position.y, position.z)
    self.origin = origin
end

function colshape_sphere:is_position_inside(position)
    return #(position - self.position) <= self.radius
end

function colshape_sphere:draw(r, g, b, a)
    if (lib.is_server) then return end

    local f_radius = numdeci(self.radius)
    DrawMarker(28, self.position.x, self.position.y, self.position.z, 0, 0, 0, 0, 0, 0, f_radius, f_radius, f_radius, r, g, b, a, false, false, 0, false, nil, nil, false)
end

function colshape_sphere:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }

    self:draw(color.r, color.g, color.b, color.a)
end

return colshape_sphere
