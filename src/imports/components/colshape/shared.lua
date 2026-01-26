-- a huge courtesy to overextended team for usage of glm library

local glm = require "glm"
local glm_polygon_contains = glm.polygon.contains

local numdeci = function(value) return value + 0.0 end

local native = {
    draw_marker = DrawMarker,
    draw_box = DrawBox,
    player_ped_id = PlayerPedId,
    get_entity_coords = GetEntityCoords,
    draw_line = DrawLine,
    draw_poly = DrawPoly,
    world3d_to_screen2d = World3dToScreen2d,
    set_text_scale = SetTextScale,
    set_text_colour = SetTextColour,
    set_text_dropshadow = SetTextDropshadow,
    set_text_edge = SetTextEdge,
    set_text_outline = SetTextOutline,
    set_text_entry = SetTextEntry,
    add_text_component_string = AddTextComponentString,
    draw_text = DrawText,
}

local function draw_text_3d_dbg(text, point)
    local on_screen, x, y = native.world3d_to_screen2d(point.x, point.y, point.z)
    if not (on_screen) then return end

    native.set_text_scale(0.0, 0.25)
    native.set_text_colour(255, 255, 255, 255)
    native.set_text_dropshadow(0, 0, 0, 0, 255)
    native.set_text_edge(2, 0, 0, 0, 150)
    native.set_text_outline()
    native.set_text_entry("STRING")
    native.add_text_component_string(text)
    native.draw_text(x, y)
end

local function draw_origin_dbg(colshape)
    local origin = colshape.origin
    local position = GetEntityCoords(PlayerPedId(), false)
    local dist = #(origin.xyz - position)
    native.draw_marker(28, origin.x, origin.y, origin.z, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 255, 0, 0, 255, false, false, 2, false, nil, nil, false)
    draw_text_3d_dbg(("%.4f"):format(dist), origin)
end

local function colshape_classwarp(class, ...)
    return setmetatable({
        new = class.new,
        is_a = function(obj)
            return getmetatable(obj) == class
        end,
    }, {
        __call = function(t, ...)
            return t.new(...)
        end,
    })
end

-- colshape
local colshape = {}
colshape.__index = colshape

function colshape.new()
    local self = {}
    self.origin = vec(0.0, 0.0, 0.0)

    return setmetatable(self, colshape)
end

function colshape:is_position_inside(position)
    return false
end

function colshape:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)
end

local colshape_circle = {}
colshape_circle.__index = colshape_circle

function colshape_circle.new(position, radius)
    lib.validate.type.assert(position, "vector3", "vector4", "table")
    lib.validate.type.assert(radius, "number")

    local self = setmetatable({}, colshape_circle)
    self.radius = numdeci(radius)
    self.position = vec(position.x, position.y)
    self.origin = vec(position.x, position.y, 0.0)

    return self
end

function colshape_circle:is_position_inside(position)
    local point = vec(position.x, position.y)
    return #(point - self.position) <= self.radius
end

function colshape_circle:draw(r, g, b, a)
    if (lib.is_server) then return end

    local pos = self.position
    local rad = self.radius
    native.draw_marker(1, pos.x, pos.y, -10000.0, 0, 0, 0, 0, 0, 0, rad * 2.0, rad * 2.0, 20000.0, r, g, b, a, false, false, 2, false, nil, nil, false)
end

function colshape_circle:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)

    local ped = native.player_ped_id()
    local coords = native.get_entity_coords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }

    self:draw(color.r, color.g, color.b, color.a)
end

-- colshape_sphere
local colshape_sphere = {}
colshape_sphere.__index = colshape_sphere
setmetatable(colshape_sphere, { __index = colshape })

function colshape_sphere.new(position, radius)
    lib.validate.type.assert(position, "vector3", "vector4", "table")
    lib.validate.type.assert(radius, "number")

    local self = setmetatable(colshape.new(), colshape_sphere)
    self.radius = radius
    self.position = vec(position.x, position.y, position.z)
    self.origin = vec(position.x, position.y, position.z)

    return self
end

function colshape_sphere:is_position_inside(position)
    return #(position - self.position) <= self.radius
end

function colshape_sphere:draw(r, g, b, a)
    if (lib.is_server) then return end

    local f_radius = numdeci(self.radius)
    native.draw_marker(28, self.position.x, self.position.y, self.position.z, 0, 0, 0, 0, 0, 0, f_radius, f_radius, f_radius, r, g, b, a, false, false, 0, false, nil, nil, false)
end

function colshape_sphere:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)

    local ped = native.player_ped_id()
    local coords = native.get_entity_coords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }

    self:draw(color.r, color.g, color.b, color.a)
end

-- colshape_poly
local colshape_poly = {}
colshape_poly.__index = colshape_poly
setmetatable(colshape_poly, { __index = colshape })

function colshape_poly.new(in_points, in_min_z, in_max_z)
    in_min_z = in_min_z or -10000.0
    in_max_z = in_max_z or 10000.0

    lib.validate.type.assert(in_points, "table")
    lib.validate.type.assert(in_min_z, "number")
    lib.validate.type.assert(in_max_z, "number")

    local self = setmetatable(colshape.new(), colshape_poly)
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
    self.origin = origin / #self.points
    self.radius = -math.huge
    for i = 1, #self.points do
        local dist = #(self.points[i] - self.origin)
        if (dist > self.radius) then
            self.radius = dist
        end
    end

    return self
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
    native.draw_marker(28, self.origin.x, self.origin.y, self.origin.z, 0, 0, 0, 0, 0, 0, f_radius, f_radius, f_radius, r, g, b, a, false, false, 0, false, nil, nil, false)

    for i = 1, #points do
        local current_point = points[i]
        local next_point    = points[(i % #points) + 1]

        local cx, cy        = current_point.x, current_point.y
        local nx, ny        = next_point.x, next_point.y

        native.draw_poly(cx, cy, min_z, nx, ny, min_z, cx, cy, min_z + z_offset, r, g, b, a)
        native.draw_poly(nx, ny, min_z, nx, ny, min_z + z_offset, cx, cy, min_z + z_offset, r, g, b, a)
        native.draw_poly(cx, cy, min_z + z_offset, nx, ny, min_z + z_offset, cx, cy, min_z, r, g, b, a)
        native.draw_poly(nx, ny, min_z + z_offset, nx, ny, min_z, cx, cy, min_z, r, g, b, a)

        if (draw_lines) then
            native.draw_line(cx, cy, min_z, nx, ny, min_z, 255, 0, 0, 255)
            native.draw_line(cx, cy, min_z + z_offset, nx, ny, min_z + z_offset, 255, 0, 0, 255)
            native.draw_line(cx, cy, min_z, cx, cy, min_z + z_offset, 255, 0, 0, 255)
        end
    end
end

function colshape_poly:draw_debug()
    if (lib.is_server) then return end

    draw_origin_dbg(self)

    local ped                 = native.player_ped_id()
    local coords              = native.get_entity_coords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color               = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }
    local r, g, b, a          = color.r, color.g, color.b, color.a

    self:draw(r, g, b, a, true)
end

lib_module.circle = colshape_classwarp(colshape_circle)
lib_module.sphere = colshape_classwarp(colshape_sphere)
lib_module.poly = colshape_classwarp(colshape_poly)
