floor = math.floor
ceil = math.ceil
abs = math.abs
round = math.round
fmt = string.format
flip = gfx.flip
spr = gfx.new
border = gfx.border
rnd = math.random
inp = sys.input
mouse = input.mouse
keydown = input.keydown

local function make_wrapper(name)
	_G[name] = function(...)
		return screen[name](screen, ...)
	end
end

for _, n in ipairs { 'clear', 'pixel', 'fill', 'line', 'lineAA',
	'circle', 'circleAA', 'fill_circle', 'fill_triangle',
	'fill_poly', 'poly' } do
	make_wrapper(n)
end
