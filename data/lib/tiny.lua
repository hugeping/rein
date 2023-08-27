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
tostr = tostring
tonum = tonumber

local px, py = 0, 0
print = function(t, x, y, c, scroll)
  t = t or ""
  if scroll == nil then
    scroll = not x
  end
  px, py = gfx.print(tostring(t), x or px, y or py, c or false, scroll)
  return px, py
end

println = function(...)
  local t = ""
  for _, v in ipairs {...} do
    if t ~= '' then t = t .. ' ' end
    t = t .. tostring(v)
  end
  t = t .. '\n'
  local x, y = print(t)
  px = 0
  return x, y
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

function input(msg)
  local t = {}
  local spw, sph = font:size(" ")
  local x, y = print(msg or "")
  clear(x, y, spw, sph, gfx.fg())
  while sys.running() do
    local r, v, a = sys.input()
    if r == 'text' then
      table.insert(t, v)
      clear(x, y, spw, sph, gfx.bg())
      x, y = print(v, x, y)
      clear(x, y, spw, sph, gfx.fg())
    elseif r == 'keydown' then
      if v == 'backspace' then
        if #t > 0 then
          clear(x, y, spw, sph, gfx.bg())
          x = x - spw
          clear(x, y, spw, sph, gfx.bg())
          clear(x, y, spw, sph, gfx.fg())
        end
        table.remove(t, #t)
      elseif v == 'return' then
        clear(x, y, spw, sph, gfx.bg())
        println()
        return table.concat(t, '')
      end
    end
    gfx.flip(1, true)
  end
  clear(x, y, spw, sph, gfx.bg())
  return ''
end
