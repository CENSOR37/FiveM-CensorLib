local colshape_poly = cslib.colshape.poly({
    vec(-1323.5826, -2900.7131, 13.9459, 224.2749),
    vec(-1338.5830, -2929.1367, 1000.9449, 9.4343),
    vec(-1292.7269, -3020.5664, 16.4445, 328.9092),
    vec(-1205.9950, -3008.3230, 13.9445, 21.6975),
    vec(-1190.2236, -2979.5793, 13.9484, 160.8254),
    vec(-1248.9374, -2903.4055, 23.4445, 207.1748),
}, -100, 100)

local colshape_circle = cslib.colshape.circle(vec(-1525.2119, -2934.6089, 13.9445, 125.8903), 100)

local colshape_sphere = cslib.colshape.sphere(vec(-1436.7086, -3201.9619, 13.9410, 230.2316), 100)

cslib.on_tick(function()
    colshape_poly:draw_debug()
    colshape_circle:draw_debug()
    colshape_sphere:draw_debug()
end)
