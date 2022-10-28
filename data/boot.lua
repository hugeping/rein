require "tiny"

local W, H = screen:size()
local logo = spr(DATADIR..'/icon.png')
local w, h = logo:size()
logo = logo:scale(0.5)
logo:blend(screen, 4, 6)
local frames = 0

printf(40, 4, 0, fmt([[REIN %s
Usage:rein <lua file>

(c)2022 Peter Kosyh
https://hugeping.ru]], VERSION))
border(7)

while true do
	frames = frames + 1
	local fl = floor(frames / 25)%2
	border(fl == 1 and 7 or 12)
	flip(1/30)
end
