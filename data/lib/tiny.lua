floor = math.floor
ceil = math.ceil
abs = math.abs
sqrt = math.sqrt
round = math.round
fmt = string.format
flip = gfx.flip
border = gfx.border
rnd = math.random
inp = sys.input
mouse = input.mouse
keydown = input.keydown
keypress = input.keypress
dprint = print
max = math.max
min = math.min

local px, py = 0, 0
print = function(t, x, y, c, scroll)
  if scroll == nil then
    scroll = not x
  end
  px, py = gfx.print(t, x or px, y or py, c or false, scroll)
  return px, py
end

println = function(t, ...)
  if t ~= nil then t = tostring(t) .. '\n' end
  return print(t, ...)
end

printf = gfx.printf
add = table.insert
del = table.remove
cos = math.cos
sin = math.sin
loadmap = gfx.loadmap
loadspr = gfx.new
spr = gfx.spr

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
  'fill_poly', 'poly', 'polyAA', 'fill_rect', 'rect', 'rectAA',
  'clip', 'noclip', 'offset', 'nooffset' } do
  make_wrapper(n)
end
