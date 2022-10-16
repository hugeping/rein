fg(15)
bg(0)

stars = {}

for i=1, 128 do
	table.insert(stars, {
		x = math.random(512),
		y = math.random(512),
		c = math.random(16),
		s = math.random(8),
	})
end

local fps = 0
local start = time()
local frames = 0

while true do
	local cur = time()
	fps = math.floor(frames / (cur - start))
	clear(0)
	local mx, my, mb = mouse()
	printf(0, 0, "FPS: %d\nMouse: %d, %d %s",
		fps, mx, my, mb.left and 'left' or '')
	for k, v in ipairs(stars) do
		pixel(v.x, v.y, v.c)
		stars[k].y = v.y + v.s
		if stars[k].y > 512 then
			stars[k].y = 0
		end
	end
	flip(1/50)
	frames = frames + 1
end
