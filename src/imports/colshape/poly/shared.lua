local lib = require "src.imports._lib.shared"
local common = require "src.imports.colshape._common.shared"
local class = require "src.imports.class.shared"
local draw_origin_dbg = common.draw_origin_dbg
local colshape = common.colshape_base_class
local numdeci = common.numdeci

local glm = require "glm"
local glm_polygon_contains = glm.polygon.contains

-- colshape_poly
local colshape_poly = class.extends(colshape)

function colshape_poly:constructor(in_points, in_min_z, in_max_z)
    in_min_z = in_min_z or -10000.0
    in_max_z = in_max_z or 10000.0

    lib.validate.type.assert(in_points, "table")
    lib.validate.type.assert(in_min_z, "number")
    lib.validate.type.assert(in_max_z, "number")

    self.points = {}
    self.min_z = numdeci(in_min_z)
    self.max_z = numdeci(in_max_z)
    local poly_z = (self.min_z + self.max_z) / 2.0
    for i = 1, #in_points do
        self.points[i] = vec(in_points[i].x, in_points[i].y, poly_z)
    end
    self.polygon = glm.polygon.new(self.points)
    self.thickness = (self.max_z - self.min_z) / 4.0

    local origin = vec(0.0, 0.0, 0.0)
    for i = 1, #self.points do
        origin = origin + self.points[i]
    end
    self.super:constructor("poly", origin / #self.points, in_points, in_min_z, in_max_z)
    self.radius = -math.huge

    local dist = math.abs(self.max_z - self.min_z) / 2.0
    if (dist > self.radius) then
        self.radius = dist
    end

    for i = 1, #self.points do
        local dist = #(self.points[i] - self.origin)
        if (dist > self.radius) then
            self.radius = dist
        end
    end
end

function colshape_poly:native_args()
    local points_flat = {}
    for i = 1, #self.points do
        table.insert(points_flat, self.points[i].x)
        table.insert(points_flat, self.points[i].y)
    end
    return self.min_z, self.max_z, points_flat
end

function colshape_poly:is_position_inside(position)
    local point = vec(position.x, position.y, position.z)
    return glm_polygon_contains(self.polygon, point, self.thickness)
end

function colshape_poly:draw(r, g, b, a, draw_lines)
    if (lib.is_server) then return end

    local points   = self.points
    local min_z    = self.min_z or -10000.0
    local top_z    = self.max_z or 10000.0
    local z_offset = top_z - min_z

    local f_radius = numdeci(self.radius)
    DrawMarker(28, self.origin.x, self.origin.y, self.origin.z, 0, 0, 0, 0, 0, 0, f_radius, f_radius, f_radius, r, g, b, a, false, false, 0, false, nil, nil, false)

    for i = 1, #points do
        local current_point = points[i]
        local next_point    = points[(i % #points) + 1]

        local cx, cy        = current_point.x, current_point.y
        local nx, ny        = next_point.x, next_point.y

        DrawPoly(cx, cy, min_z, nx, ny, min_z, cx, cy, min_z + z_offset, r, g, b, a)
        DrawPoly(nx, ny, min_z, nx, ny, min_z + z_offset, cx, cy, min_z + z_offset, r, g, b, a)
        DrawPoly(cx, cy, min_z + z_offset, nx, ny, min_z + z_offset, cx, cy, min_z, r, g, b, a)
        DrawPoly(nx, ny, min_z + z_offset, nx, ny, min_z, cx, cy, min_z, r, g, b, a)

        if (draw_lines) then
            DrawLine(cx, cy, min_z, nx, ny, min_z, 255, 0, 0, 255)
            DrawLine(cx, cy, min_z + z_offset, nx, ny, min_z + z_offset, 255, 0, 0, 255)
            DrawLine(cx, cy, min_z, cx, cy, min_z + z_offset, 255, 0, 0, 255)
        end
    end
end

function colshape_poly:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)

    local ped                 = PlayerPedId()
    local coords              = GetEntityCoords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color               = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }
    local r, g, b, a          = color.r, color.g, color.b, color.a

    self:draw(r, g, b, a, true)
end

return colshape_poly
