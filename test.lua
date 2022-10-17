fg(15)
bg(0)
local w = 256
local h = 256
stars = {}

for i=1, 128 do
	table.insert(stars, {
		x = math.random(w),
		y = math.random(h),
		c = math.random(16),
		s = math.random(8),
	})
end

local fps = 0
local start = time()
local frames = 0
local txt = ''

while true do
	local cur = time()
	fps = math.floor(frames / (cur - start))
	clear(0)
	local mx, my, mb = mouse()
	local a, b = input()
	if b then
		txt = txt .. b
	elseif a == 'backspace' then
		txt = ''
	end
	printf(0, 0, "FPS:%d\nМышь:%d,%d %s\nInp:%s",
		fps, mx, my, mb.left and 'left' or '', txt)
	for k, v in ipairs(stars) do
		pixel(v.x, v.y, v.c)
		stars[k].y = v.y + v.s
		if stars[k].y > h then
			stars[k].y = 0
			stars[k].x = math.random(w)
		end
	end
	flip(1/50)
	frames = frames + 1
end
