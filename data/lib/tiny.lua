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
keypress = input.keypress
dprint = print
print = gfx.print
printf = gfx.printf
add = table.insert
del = table.remove
cos = math.cos
sin = math.sin

all = function(t)
	local n = #t
	local i = 0
	return function()
		i = i + 1
		return t[i]
	end
end

local function make_wrapper(name)
  _G[name] = function(...)
    return screen[name](screen, ...)
  end
end

for _, n in ipairs { 'clear', 'pixel', 'fill', 'line', 'lineAA',
  'circle', 'circleAA', 'fill_circle', 'fill_triangle',
  'fill_poly', 'poly', 'polyAA', 'fill_rect', 'rect', 'rectAA' } do
  make_wrapper(n)
end
