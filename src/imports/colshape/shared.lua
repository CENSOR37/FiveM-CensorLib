local colshape_circle = require "src.imports.colshape.circle.shared"
local colshape_sphere = require "src.imports.colshape.sphere.shared"
local colshape_poly = require "src.imports.colshape.poly.shared"

local out_colshape = {}

out_colshape.circle = colshape_circle
out_colshape.sphere = colshape_sphere
out_colshape.poly = colshape_poly

return out_colshape
