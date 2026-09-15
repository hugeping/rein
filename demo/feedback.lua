-- Port of a Processing sketch: sin/cos feedback point cloud.
--   W=540; N=200; x,y,t=0,0,0
-- https://x.com/yuruyurau/status/1226846058728177665
local W, N = 540, 200
local sin, cos = math.sin, math.cos
local r = math.pi * 2 / N

local x, y, t = 0, 0, 0
local col = { 0, 0, 99, 255 }

gfx.win(W, W)

local scr = screen
local pixel = scr.pixel

local function F(i, c)
  local u = sin(i + y) + sin(r * i + x)
  local v = cos(i + y) + cos(r * i + x)
  x = u + t
  y = v
  col[1], col[2] = i, c
  pixel(scr, u * N / 2 + W / 2, y * N / 2 + W / 2, col)
end

while sys.running() do
  scr:clear(0)
  for i = 0, N - 1 do
    for c = 0, N - 1 do
      F(i, c)
    end
  end
  t = t + 0.002
  gfx.flip(1/30)
end
