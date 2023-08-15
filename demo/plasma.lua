t = 0
local w, h = screen:size()
local sin, abs, cos, sqrt, floor = math.sin, math.abs, math.cos, math.sqrt, math.floor
local buf = {}

local function col2int(r, g, b, a)
  r = floor(r)
  g = floor(g)
  b = floor(b)
  a = floor(a)
--  return bit.bor(bit.lshift(r, 24), bit.lshift(g, 16), bit.lshift(b, 8), a)
  return r * 0x1000000 + g * 0x10000 + b * 0x100 + a;
end

function plasma1()
  local cx, cy, x, y, r, g, b, v
  local i = 1
  t = t + 0.1
  v = 0.0
  local rc = 0
  local val = value
  for y = 0, h-1 do
    for x = 0, w-1 do
      cx = x / 100 - .25 - .5 + 0.5 * sin(t / 5)
      cy = y / 75 - .25 - .5 + 0.5 * cos(t / 3)
      v = v + sin(sqrt(100 * (cx * cx + cy * cy) + t) + t)
      v = v + sin(x / 25 + t)
      v = v + sin(y / 25 + t)
      v = v / 5
      r = abs(sin(v * 3.14)) * 255
      g = abs(sin(v * 3.14 + 4 * 3.14 / 3)) * 255
      b = abs(sin(v * 3.14 + 2 * 3.14 / 3)) * 255
      buf[i] = col2int(r, g, b, 255)
      i = i + 1
    end
  end
end

function plasma2()
  local cx, cy, x, y, r, g, b, v
  local i = 1
  t = t + 0.1
  v = 0.0
  for y = 0, h-1 do
    for x = 0, w-1 do
      cx = x / 100 - .25 - .5 + 0.5 * sin(t / 5)
      cy = y / 75 - .25 - .5 + 0.5 * cos(t / 3)
      v = v + sin(sqrt(100 * (cx * cx + cy * cy) + t) + t)
      v = v + sin(x / (25 + t) + y / (50 + t))
      v = v + sin(y / (25 + t) + x / (50 + t))
      v = v / 4
      r = abs(sin(v * 3.14)) * 255
      g = abs(sin(v * 3.14 + 4 * 3.14 / 3)) * 255
      b = abs(sin(v * 3.14 + 2 * 3.14 / 3)) * 255
      buf[i] = col2int(r, g, b, 255)
      i = i + 1
    end
  end
end

function plasma3()
  local cx, cy, x, y, r, g, b, v
  local i = 1
  t = t + 0.1
  v = 0.0
  for y = 0, h-1 do
    for x = 0, w-1 do
      cx = x / 100 - .25 - .5 + 0.5 * cos(t / 5)
      cy = y / 75 - .25 - .5 + 0.5 * sin(t / 3)
      v = v + sin(sqrt(100 * (cx * cx + cy * cy) + t) + t / 2)
      v = v + sin(sqrt(x / 1000 + t + x + y / 1000 * y))
      v = v + cos(sqrt(y / 1000 + t + y + x / 1000 * x))
      v = v / 4
      r = abs(sin(v * 3.14)) * 255
      g = abs(sin(v * 3.14 + 4 * 3.14 / 3)) * 255
      b = abs(sin(v * 3.14 + 2 * 3.14 / 3)) * 255
      buf[i] = col2int(r, g, b, 255)
      i = i + 1
    end
  end
end

function plasma4()
  local cx, cy, x, y, r, g, b, v
  local i = 1
  t = t + 0.1
  v = 0.0
  for y = 0, h-1 do
    for x = 0, w-1 do
      v = sqrt(x / (y + 15) + t)
      v = v + sin(x / 100 + t)
      v = v + cos(y / 100 + t)
      v = v / 2
      r = abs(sin(v * 3.14)) * 255
      g = abs(sin(v * 3.14 + 4 * 3.14 / 3)) * 255
      b = abs(sin(v * 3.14 + 2 * 3.14 / 3)) * 255
      buf[i] = col2int(r, g, b, 255)
      i = i + 1
    end
  end
end

function plasma5()
  local v
  t = floor(t) + 1
  local i = 1
  for y = 0, h-1 do
    for x = 0, w-1 do
      v = (x * x + y * y + t) % 256
      buf[i] = col2int(0, v, v, v/2)
      i = i + 1
    end
  end
end

function plasma6()
  local x, y, r, g, b, v
  t = t + 0.1
  v = 0.0
  local i = 1
  for y = 0, h-1 do
    for x = 0, w-1 do
      v = x * x
      v = v * y * y + sin(t * 2) * 100
      r = v / 2
      g = v
      b = v + v
      buf[i] = col2int(r, g, b, 255)
      i = i + 1
    end
  end
end

local demo = { plasma1, plasma2, plasma3, plasma4, plasma5, plasma6 }

local demo_nr = 1

local fps = 0
while sys.running() do
  demo[demo_nr]()
  screen:buff(buf)

  local r, v = sys.input()

  if r == 'keydown' and v == 'space' then
    demo_nr = demo_nr + 1
    if demo_nr > #demo then demo_nr = 1 end
  end

  screen:clear(0,256-8,256,256-8,7)
  gfx.printf(0, 256-8, 1, "Демо:%d FPS:%d", demo_nr, fps)
  fps = gfx.flip(0)
end
