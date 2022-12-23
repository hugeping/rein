local W, H = screen:size()

-- select text betwin [[ and ]]
-- and press f8

local hello = gfx.new[[
---3-------b----
b3--b3-bbbb-b3---b3---bbbb3
b3--b3-b333-b3---b3---b3-b3
b3--b3-b3---b3---b3---b3-b3
bbbbb3-bbbb-b3---b3---b3-b3
b333b3-b333-b3---b3---b3-b3
b3--b3-b3---b3---b3---b3-b3
b3--b3-bbbb-bbbb-bbbb-bbbb3
33--33-3333-3333-3333-33333
]]

print("debug: hello is pixels!", hello)

function run()
  local y, dx = 0, 8
  local w, h = hello:size()
  while sys.running() do
    screen:clear(15)
    hello:blend(screen, (W - w)/2, y)
    y = y + dx
    if y >= H - h or y <= 0 then
      dx = -dx
    end
    gfx.flip(1/30)
  end
end

run()
