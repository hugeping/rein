local spr = {[[
---------------*
	-**-**--
	*--*--*-
	*-----*-
	-*---*--
	--*-*---
	---*----
	--------
	--------
]], [[
---------------*
	-**-**--
	*******-
	*******-
	-*****--
	--***---
	---*----
	--------
	--------
]]
}
local w, h = screen:size()
stars = {}

for i=1, #spr do
	spr[i] = gfx.new(spr[i])
end

for i=1, 128 do
	table.insert(stars, {
		x = math.random(w),
		y = math.random(h),
		c = math.random(16),
		s = math.random(8),
	})
end

local fps = 0
local start = sys.time()
local frames = 0
local txt = ''

local function showkeys()
	local t = ''
	local k = { 'left', 'right', 'up', 'down', 'space', 'z', 'x' }
	for _, v in ipairs(k) do
		if input.keydown(v) then
			t = t .. v .. ' '
		end
	end
	return t
end

beep1 = function()
	for k=0,1000,0.1 do
		sys.yield(math.sin(k))
	end
end

beep2 = function()
	for k=0,2000,0.3 do
		sys.yield(math.sin(k))
	end
end

local SR = 44100
local TWO_PI_BY_SR = 2 * math.pi / SR

local sfx = {
}

function sfx.sin(t, freq)
	return math.sin(TWO_PI_BY_SR * freq * t)
end

function sfx.dsf(t, freq, modscale, modamp, width)
	local f1 = TWO_PI_BY_SR * freq * t
	local f2 = modscale * f1
	local ww = width * width
	local e1 = math.sin(f1) - width * modamp * math.sin(f1 - f2)
	local e2 = 1 + ww - 2 * width * modamp * math.cos(f2)
	return e1 / e2
end

function sfx.saw(t, freq, width)
	width = width or 0.5
	return sfx.dsf(t, freq, 1, 1, width)
end

function sfx.square(t, freq, width)
	width = width or 0.5
	return sfx.dsf(t, freq, 2, 1, width)
end

local abs = math.abs

beep3 = function()
	for t = 0, SR * 4, 1 do
		sys.yield(0.3 * sfx.sin(t, 2) * sfx.dsf(t, 450, 0.120, 1, 0.1 + 0.7 * abs(sfx.sin(t, 0.2))))
	end
end

mixer.add(beep3)
--mixer.add(beep1)
--mixer.add(beep2)
local s = gfx.new
[[
-------78-----e-
-----------
--8888888--
-8-------8-
-8-78-78-8-
-8-------8-
-8---e---8-
-8---e---8-
-8-e---e-8-
-8--eee--8-
-8-------8-
--8888888--
-----------
]];
while true do
	local cur = sys.time()
	fps = math.floor(frames / (cur - start))
	screen:clear(0)
	screen:fill_circle(100, 100, 30, s)
	screen:offset(math.floor(math.sin(frames * 0.1)*6), math.floor(math.cos(frames * 0.1)*6))
	spr[math.floor(frames/10)%2+1]:blend(screen, 240, 0)

	local mx, my, mb = input.mouse()
	local a, b = sys.input()

	if a == 'text' then
		txt = txt .. b
	elseif a == 'keydown' and b == 'return' then
		txt = txt .. '\n'
	elseif a == 'keydown' and b == 'backspace' then
		txt = ''
	end

	printf(0, 0, 15, "FPS:%d\nМышь:%d,%d %s\nKeys:%s\nInp:%s",
		fps, mx, my, mb.left and 'left' or '',
		showkeys(), txt..'\1')

	for k, v in ipairs(stars) do
		screen:pixel(v.x, v.y, v.c)
		stars[k].y = v.y + v.s
		if stars[k].y > h then
			stars[k].y = 0
			stars[k].x = math.random(w)
		end
	end
	gfx.flip(1/50)
	frames = frames + 1
end
