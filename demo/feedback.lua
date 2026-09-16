-- Same Processing sketch, drawn with a single pixels{} call:
-- the whole frame is a flat { index, color, ... } table.
--   W=540; N=200; x,y,t=0,0,0
local W, N = 540, 200
local sin, cos, floor = math.sin, math.cos, math.floor
local r = math.pi * 2 / N

local x, y, t = 0, 0, 0

gfx.win(W, W)

local scr = screen
local pts = {}

while sys.running() do
  scr:clear(0)
  local k = 1
  for i = 0, N - 1 do
    local cr = i * 0x1000000
    for c = 0, N - 1 do
      local u = sin(i + y) + sin(r * i + x)
      local v = cos(i + y) + cos(r * i + x)
      x = u + t
      y = v
      local idx = floor(y * N / 2 + W / 2) * W +
        floor(u * N / 2 + W / 2) + 1
      pts[k] = idx
      pts[k + 1] = cr + c * 0x10000 + 99 * 0x100 + 255
      k = k + 2
    end
  end
  scr:pixels(pts)
  t = t + 0.002
  gfx.flip(1/30)
end
