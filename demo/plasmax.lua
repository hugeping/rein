local w, h = screen:size()
local sin, abs, cos, sqrt, floor = math.sin, math.abs, math.cos, math.sqrt, math.floor
function render()
  local t = 0
  local sin, abs, cos, sqrt, floor = math.sin, math.abs, math.cos, math.sqrt, math.floor

  local buf = {}

  local function col2int(r, g, b, a)
    local floor = math.floor
    r = floor(r)
    g = floor(g)
    b = floor(b)
    a = floor(a)
    return r * 0x1000000 + g * 0x10000 + b * 0x100 + a;
  end

  local demos = {
    function(scr, fx, fy, w, h)
      local cx, cy, x, y, r, g, b, v
      local i = 1
      t = t + 0.1
      v = 0.0
      local rc = 0
      local val = value
      for y = fy, fy + h-1 do
        for x = fx, fx + w-1 do
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
    end,
    function(scr, fx, fy, w, h)
      local cx, cy, x, y, r, g, b, v
      local i = 1
      t = t + 0.1
      v = 0.0
      for y = fy, fy + h-1 do
        for x = fx, fx + w-1 do
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
    end,
    function(scr, fx, fy, w, h)
      local cx, cy, x, y, r, g, b, v
      local i = 1
      t = t + 0.1
      v = 0.0
      for y = fy, fy + h-1 do
        for x = fx, fx+w-1 do
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
    end,
    function(scr, fx, fy, w, h)
      local cx, cy, x, y, r, g, b, v
      local i = 1
      t = t + 0.1
      v = 0.0
      for y = fy, fy+h-1 do
        for x = fx, fx+w-1 do
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
    end,
    function(scr, fx, fy, w, h)
      local v
      t = floor(t) + 1
      local i = 1
      for y = fy, fy+h-1 do
        for x = fx, fx+w-1 do
          v = (x * x + y * y + t) % 256
          buf[i] = col2int(0, v, v, v/2)
          i = i + 1
        end
      end
    end,
    function(scr, fx, fy, w, h)
      local x, y, r, g, b, v
      t = t + 0.1
      v = 0.0
      local i = 1
      for y = fy, fy+h-1 do
        for x = fx, fx+w-1 do
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
  }
  local demo_nr = 1
  local scr, x, y, w, h = thread:read()
  print("Thread: ", scr, x, y, w, h)
  while scr do
    demos[demo_nr](scr, x, y, w, h)
    local cmd = thread:read()
    scr:buff(buf, x, y, w, h)
    if not cmd or cmd == 'quit' then
      break
    end
    if cmd == 'next' then
      demo_nr = demo_nr + 1
      if demo_nr > #demos then demo_nr = 1 end
    end
    if not thread:write() then
      break
    end
  end
  print ("Thread end")
end

local THREADS = 4
local thr = {}

function start_demo(n)
  local d = h / THREADS
  for i=1, THREADS do
    local a = thread.start(render)
    a:write(screen, 0, (i-1)*d, w, d)
    thr[i] = a
  end
end

local fps = 0

start_demo()

while sys.running() do
  for i=1, THREADS do
    thr[i]:write 'render'
  end

  for i=1, THREADS do
    thr[i]:read()
  end

  local r, v = sys.input()

  if r == 'keydown' and v == 'space' then
    for i=1, THREADS do
      thr[i]:write 'next'
      thr[i]:read()
    end
  end

  screen:clear(0,w-8,w,h-8,7)
  gfx.printf(0, h-8, 1, "Демо:%d FPS:%d", 1, fps)
  fps = gfx.flip(0)
end

print "quitting..." -- nothing to do, will exit on next cycle
for i=1, THREADS do
  thr[i]:write 'quit'
end
