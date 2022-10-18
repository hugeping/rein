w, h = screen:size()
local floor = math.floor
local ceil = math.ceil
local spr = {}

spr.X = sprite [[
*
--------
-*---*-
--*-*--
---*---
--*-*--
-*---*-
-------
]]

pal = {
	x = 0;
	y = 0;
	w = 16*2;
	h = 16*8;
	color = 0;
	lev = -1;
}

function pal:show()
	local s = self
	local w = floor(s.w / 2)
	local h = floor(s.h / 8)
	local x, y = self.x, self.y
	for y=0, 7 do
		clear(x, y*h, w, h, color(y))
		clear(x+w, y*h, w, h, color(y+8))
	end
	local n = s.color
	if n >= 8 then
		x = x + w
		n = n - 8
	end
	y = n
	poly({x, y*h,
		x + w - 1, y*h,
		x + w -1, y*h + h - 1,
		x, y*h + h - 1}, 7)
end

function pal:pos2col(x, y)
	local s = self
	local w = floor(s.w / 2)
	local h = floor(s.h / 8)
	x = x - s.x
	y = y - s.y
	x = floor(x/w)
	y = floor(y/h)
	return x*8 + y
end

function pal:click(x, y, mb)
	local c = self:pos2col(x, y)
	if not c then
		return
	end
	self.color = c
	return true
end

grid = {
	x = 0;
	y = 0;
	w = 256;
	h = 256;
	grid = 16;
	lev = 1;
	pixels = {
	};
}

local obj = { pal, grid }

function grid:pos2cell(x, y)
	local s = self
	x = x - s.x
	y = y - s.y
	x = floor(x/s.grid) + 1
	y = floor(y/s.grid) + 1
	return x, y
end

function grid:click(x, y, mb)
	local s = self
	x, y = s:pos2cell(x, y)
	if not x then
		return
	end
	s.pixels[y] = s.pixels[y] or {}
	if mb.right then
		s.pixels[y][x] = nil
	else
		s.pixels[y][x] = pal.color
	end
	return true
end

function grid:show()
	local s = self
	local dx = floor(self.w / s.grid)
	clear(s.x, s.y, s.w, s.h, 1)
	local Xd = spr.X:size()
	Xd = (dx - Xd)/2
	for y=1,s.grid do
		for x=1,s.grid do
			local c = s.pixels[y] and s.pixels[y][x]
			if not c then
				clear(s.x+(x-1)*dx, s.y+(y-1)*dx, dx, dx, 1)
				blend(spr.X, s.x+(x-1)*dx + Xd, s.y+(y-1)*dx + Xd)
			else
				clear(s.x+(x-1)*dx, s.y+(y-1)*dx, dx, dx, c)
			end
		end
	end
	poly({s.x, s.y,
		s.x + s.w, s.y,
		s.x+s.w, s.y+s.h,
		s.x, s.y+s.h}, 0)
	for x=1,s.grid do
		line(s.x+(x-1)*dx, s.y, (x-1)*dx, s.y + s.h, 0)
		line(s.x, s.y+(x-1)*dx, s.x+s.w, s.y+(x-1)*dx, 0)
	end
end

while true do
	fill(1)
	table.sort(obj, function(a, b) return a.lev > b.lev end)
	for _, v in ipairs(obj) do
		v:show()
	end
	table.sort(obj, function(a, b) return a.lev <= b.lev end)
	local r, e = input() -- todo
	local mx, my, mb = mouse()
	if mb.left or mb.right then
		for _, v in ipairs(obj) do
			local mx, my, mb = mouse()
			if mx >= v.x and my >= v.y and
				mx < v.x + v.w and
				my < v.y + v.h then
				if v:click(mx, my, mb) then
					break
				end
			end
		end
	end
	flip(1/25)
end
