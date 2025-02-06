local color = {}
color.__index = color

local function clamp_color_value(value)
    return math.max(0, math.min(255, math.floor(value)))
end

function color:rgb()
    return { r = self.r, g = self.g, b = self.b }
end

function color:rgba()
    return { r = self.r, g = self.g, b = self.b, a = self.a }
end

function color:hex()
    if (self.a == 255) then
        return string.format("%02X%02X%02X", self.r, self.g, self.b)
    end

    return string.format("%02X%02X%02X%02X", self.r, self.g, self.b, self.a)
end

-- static funcction
function color.form_rgba(r, g, b, a)
    lib.validate.type.assert(r, "number")
    lib.validate.type.assert(g, "number")
    lib.validate.type.assert(b, "number")
    lib.validate.type.assert(a, "number")

    local self = {}
    self.r = clamp_color_value(r)
    self.g = clamp_color_value(g)
    self.b = clamp_color_value(b)
    self.a = clamp_color_value(a or 255)

    return setmetatable(self, {
        __index = function(t, k)
            if (color[k]) then
                return color[k](self)
            end
        end,
    })
end

function color.form_rgb(r, g, b)
    return color.form_rgba(r, g, b, 255)
end

function color.form_hex(hex)
    lib.validate.type.assert(hex, "string")

    hex = hex:gsub("#", ""):upper()

    assert(#hex == 6 or #hex == 8, "Invalid hex color format. Must be #RRGGBB or #RRGGBBAA")

    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    local a = #hex == 8 and tonumber(hex:sub(7, 8), 16) or 255

    assert(r and g and b and a, "Invalid hex color values")

    return color.from_rgba(r, g, b, a)
end

lib_module.rgba = color.form_rgba
lib_module.rgb = color.form_rgb
lib_module.hex = color.form_hex
