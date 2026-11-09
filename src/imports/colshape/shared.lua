local common = require "src.imports.colshape._common.shared"
local colshape_circle = require "src.imports.colshape.circle.shared"
local colshape_sphere = require "src.imports.colshape.sphere.shared"
local colshape_poly = require "src.imports.colshape.poly.shared"

local out_colshape = {}

out_colshape.circle = common.colshape_classwarp("circle", colshape_circle)
out_colshape.sphere = common.colshape_classwarp("sphere", colshape_sphere)
out_colshape.poly = common.colshape_classwarp("poly", colshape_poly)

return out_colshape
