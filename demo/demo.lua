local w, h = screen:size()
local buf = {}
local t = 0

local function col2int(r, g, b, a)
  r = math.floor(r)
  g = math.floor(g)
  b = math.floor(b)
  a = math.floor(a)
  return r * 0x1000000 + g * 0x10000 + b * 0x100 + a;
end

function first(x, y, t)
  local r, g, b
  r = math.abs(math.sin((y/x*3)*4+t/4)*math.sin(t*0.01))
  g = math.abs(math.sin((y/x*3)*4+t/4)*math.cos(t*0.002))
  b = math.abs(math.sin((y/x*3)*4+t/4)*math.sin(t*0.007))
  return r * 255, g * 255, b * 255
end

function second(x, y, t)
  local b
  b = math.floor((x*y+t) % 254)+1
  return b*0.1, b*0.8, b
end

function third(x, y, t)
  local b
  b = (math.tan(y*y + x*x - x/4.05 - y/4.05 + t/100) + math.sin(t/100)/2) % 254 + 1
  return b, b*0.7, 0
end

function fifth(x, y, t)
  local c = math.tan(x*y*2-x/1.475-y/1.475+t*0.008) *
    math.abs(math.sin(t*0.008)*4) % 255
  return c/3, c/2, c
end

demo = { first, second, third, fifth }
current = 1
local fps = 0

while true do
  t = t + 1
  local i = 1
  for x = 0, w-1 do
    for y = 0, h-1 do
      r, g, b = demo[current](x, y, t)
      buf[i] = col2int(r, g, b, 255)
      i = i + 1
    end
  end

  local r, v = sys.input()

  if r == 'keydown' and v == 'space' then
    current = current + 1
    if current > #demo then current = 1 end
  end

  screen:buff(buf)
  screen:clear(0,256-8,256,256-8,7)
  gfx.printf(0, 256-8, 1, "Демо:%d FPS:%d", current, fps)

  fps = gfx.flip(1/50)
end
