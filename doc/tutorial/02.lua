local text = "HELLO WORLD!"

local w, h = font:size(text)
local W, H = screen:size()

gfx.print(text, (W - w)/2, (H - h)/2)
