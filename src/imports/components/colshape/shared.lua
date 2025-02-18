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

local function table_map(table, cb)
    local new_table = {}

    for i = 1, #table do
        new_table[i] = cb(table[i], i, table)
    end

    return new_table
end

local function next_free_point(points, b, len)
    for i = 1, len do
        local n = (i + b) % len

        n = n ~= 0 and n or len

        if points[n] then
            return n
        end
    end
end

local function unable_to_split(polygon)
    print("The following polygon is malformed and has failed to be split into triangles for debug")

    for k, v in pairs(polygon) do
        print(k, v)
    end
end

local function get_triangles(polygon)
    local triangles = {}

    if polygon:isConvex() then
        for i = 2, #polygon - 1 do
            triangles[#triangles + 1] = mat(polygon[1], polygon[i], polygon[i + 1])
        end

        return triangles
    end

    if not polygon:isSimple() then
        unable_to_split(polygon)

        return triangles
    end

    local points = {}
    local polygonN = #polygon

    for i = 1, polygonN do
        points[i] = polygon[i]
    end

    local a, b, c = 1, 2, 3
    local zValue = polygon[1].z
    local count = 0

    while polygonN - #triangles > 2 do
        local a2d = polygon[a].xy
        local c2d = polygon[c].xy

        if polygon:containsSegment(vec3(glm.segment2d.getPoint(a2d, c2d, 0.01), zValue), vec3(glm.segment2d.getPoint(a2d, c2d, 0.99), zValue)) then
            triangles[#triangles + 1] = mat(polygon[a], polygon[b], polygon[c])
            points[b] = false

            b = c
            c = next_free_point(points, b, polygonN)
        else
            a = b
            b = c
            c = next_free_point(points, b, polygonN)
        end

        count += 1

        if count > polygonN and #triangles == 0 then
            unable_to_split(polygon)

            return triangles
        end

        Wait(0)
    end

    return triangles
end

local function draw_debug_polygon(triangles, polygon, thickness, color)
    for i = 1, #triangles do
        local triangles = triangles[i]
        for i = 1, #triangles do
            local triangle = triangles[i]
            native.draw_poly(triangle[1].x, triangle[1].y, triangle[1].z, triangle[2].x, triangle[2].y, triangle[2].z, triangle[3].x, triangle[3].y, triangle[3].z, color.r, color.g, color.b, color.a)
            native.draw_poly(triangle[2].x, triangle[2].y, triangle[2].z, triangle[1].x, triangle[1].y, triangle[1].z, triangle[3].x, triangle[3].y, triangle[3].z, color.r, color.g, color.b, color.a)
        end
    end

    for i = 1, #polygon do
        local thickness = vec(0, 0, thickness / 2)
        local a = polygon[i] + thickness
        local b = polygon[i] - thickness
        local c = (polygon[i + 1] or polygon[1]) + thickness
        local d = (polygon[i + 1] or polygon[1]) - thickness
        native.draw_line(a.x, a.y, a.z, b.x, b.y, b.z, color.r, color.g, color.b, 225)
        native.draw_line(a.x, a.y, a.z, c.x, c.y, c.z, color.r, color.g, color.b, 225)
        native.draw_line(b.x, b.y, b.z, d.x, d.y, d.z, color.r, color.g, color.b, 225)
        native.draw_poly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, color.r, color.g, color.b, color.a)
        native.draw_poly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, color.r, color.g, color.b, color.a)
        native.draw_poly(b.x, b.y, b.z, c.x, c.y, c.z, d.x, d.y, d.z, color.r, color.g, color.b, color.a)
        native.draw_poly(d.x, d.y, d.z, c.x, c.y, c.z, b.x, b.y, b.z, color.r, color.g, color.b, color.a)
    end
end

local function colshape_classwarp(class, ...)
    return setmetatable({
        new = class.new,
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
    return setmetatable({}, colshape)
end

function colshape:is_position_inside(position)
    return false
end

function colshape:draw_debug()
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
    return self
end

function colshape_sphere:is_position_inside(position)
    return #(position - self.position) <= self.radius
end

function colshape_sphere:draw_debug()
    if (lib.is_server) then return end

    local f_radius = self.radius + 0.0
    local ped = native.player_ped_id()
    local coords = native.get_entity_coords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }
    native.draw_marker(28, self.position.x, self.position.y, self.position.z, 0, 0, 0, 0, 0, 0, f_radius, f_radius, f_radius, color.r, color.g, color.b, color.a, false, false, 0, false, nil, nil, false)
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

    return self
end

function colshape_poly:is_position_inside(position)
    local point = vec(position.x, position.y, position.z)
    return glm.polygon.contains(self.polygon, point, self.thickness)
end

function colshape_poly:draw_debug()
    if (lib.is_server) then return end

    local ped                 = native.player_ped_id()
    local coords              = native.get_entity_coords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color               = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }
    local points              = self.points
    local min_z               = self.min_z or -10000.0
    local top_z               = self.max_z or 10000.0
    local z_offset            = top_z - min_z
    local r, g, b, a          = color.r, color.g, color.b, color.a

    for i = 1, #points do
        local current_point = points[i]
        local next_point    = points[(i % #points) + 1]

        local cx, cy        = current_point.x, current_point.y
        local nx, ny        = next_point.x, next_point.y

        native.draw_poly(cx, cy, min_z, nx, ny, min_z, cx, cy, min_z + z_offset, r, g, b, a)
        native.draw_poly(nx, ny, min_z, nx, ny, min_z + z_offset, cx, cy, min_z + z_offset, r, g, b, a)
        native.draw_poly(cx, cy, min_z + z_offset, nx, ny, min_z + z_offset, cx, cy, min_z, r, g, b, a)
        native.draw_poly(nx, ny, min_z + z_offset, nx, ny, min_z, cx, cy, min_z, r, g, b, a)

        native.draw_line(cx, cy, min_z, nx, ny, min_z, 255, 0, 0, 255)
        native.draw_line(cx, cy, min_z + z_offset, nx, ny, min_z + z_offset, 255, 0, 0, 255)
        native.draw_line(cx, cy, min_z, cx, cy, min_z + z_offset, 255, 0, 0, 255)

        draw_text_3d_dbg(tostring(i), vec(cx, cy, min_z + z_offset))
    end
end

-- colshape_box
local colshape_box = {}
colshape_box.__index = colshape_box
setmetatable(colshape_box, { __index = colshape })

function colshape_box.new(position, size, rotation)
    rotation = rotation or 0

    lib.validate.type.assert(position, "vector3", "vector4", "table")
    lib.validate.type.assert(size, "vector3", "vector4", "table")
    lib.validate.type.assert(rotation, "number")

    local self = setmetatable(colshape.new(), colshape_box)
    self.position = vec(position.x, position.y, position.z)
    self.size = vec(size.x, size.y, size.z) / 2 or vec3(2)
    self.thickness = self.size.z * 2
    self.rotation = quat(rotation or 0, vec(0, 0, 1))
    self.polygon = (self.rotation * glm.polygon.new({
        vec3(self.size.x, self.size.y, 0),
        vec3(-self.size.x, self.size.y, 0),
        vec3(-self.size.x, -self.size.y, 0),
        vec3(self.size.x, -self.size.y, 0),
    }) + self.position)

    return self
end

function colshape_box:is_position_inside(position)
    return glm_polygon_contains(self.polygon, vec(position.x, position.y, position.z), self.thickness / 4)
end

function colshape_box:draw_debug()
    if (lib.is_server) then return end

    local ped = native.player_ped_id()
    local coords = native.get_entity_coords(ped)
    local is_local_ped_inside = self:is_position_inside(coords)
    local color = is_local_ped_inside and { r = 0, g = 255, b = 0, a = 75 } or { r = 0, g = 0, b = 255, a = 75 }

    if not (self.triangles) then
        self.triangles = {
            get_triangles(glm.polygon.new(table_map(self.polygon, function(point) return point - vec(0, 0, self.thickness / 2) end))),
            get_triangles(glm.polygon.new(table_map(self.polygon, function(point) return point + vec(0, 0, self.thickness / 2) end))),
        }
    end
    draw_debug_polygon(self.triangles, self.polygon, self.thickness, color)
end

lib_module.sphere = colshape_classwarp(colshape_sphere)
lib_module.poly = colshape_classwarp(colshape_poly)
lib_module.box = colshape_classwarp(colshape_box)
