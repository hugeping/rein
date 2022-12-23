local text = "HELLO WORLD!"
local W, H = screen:size()

function run()
  local y, dx = 0, 8
  local w, h = font:size(text)
  while sys.running() do
    screen:clear(15)
    gfx.print(text, (W - w)/2, y)
    y = y + dx
    if y >= H - h or y <= 0 then
      dx = -dx
    end
    gfx.flip(1/30)
  end
end

run()
