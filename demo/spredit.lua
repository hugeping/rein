w, h = screen:size()
local floor = math.floor
local ceil = math.ceil
local spr = {}

local SPRITE = ARGS[2] or 'sprite.spr'

spr.X = sprite [[
*
*---*
-*-*-
--*--
-*-*-
*---*
]]

pal = {
	x = 0;
	y = 0;
	cw = 8;
	ch = 8;
	w = 8*2;
	h = 8*8;
	color = 0;
	lev = -1;
}

function pal:show()
	local s = self
	local w = s.cw
	local h = s.ch
	local x, y = self.x, self.y
	for y=0, 7 do
		clear(x, y*h, w, h, color(y))
		clear(x+w, y*h, w, h, color(y+8))
	end
	local n = s.color
	local c = n + 7
	if c >= 16 then c = c - 16 end
	if n >= 8 then
		x = x + w
		n = n - 8
	end
	y = n
	poly({x, y*h,
		x + w - 1, y*h,
		x + w -1, y*h + h - 1,
		x, y*h + h - 1}, c)
end

function pal:pos2col(x, y)
	local s = self
	local w = s.cw
	local h = s.ch
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
	max_grid = 64;
	min_grid = 16;
	lev = 1;
	pixels = {};
}

title = {
	x = 0;
	y = 256 - 8;
	lev = -1;
}

function title:show()
	local dirty = ' '
	if grid.dirty then
		dirty = '*'
	end
	local info = string.format("x%02d %s%s", grid.grid, SPRITE, dirty)
	local w, h = font:size(info)
	self.w = w
	self.h = h
	print(info, self.x, self.y, 15)
end

function title:click(x, y, mb, click)
	if not click then
		return true
	end
	local s = self
	x = x - s.x
	local w = font:size(string.format("x%02d", grid.grid))
	if x >= w then
		grid.dirty = false
		if mb.left then
			grid:save(SPRITE)
		elseif mb.middle then
			grid.pixels = {}
		end
	else
		if not grid:zoom(1) then
			grid:zoom(0)
		end
	end
	return true
end

local obj = { pal, grid, title }

function grid:zoom(inc)
	local g = self
	if inc < 0 then
		if g.grid > g.min_grid then
			g.grid = g.grid / 2
			return true
		end
	elseif inc > 0 then
		if g.grid < g.max_grid then
			g.grid = g.grid * 2
			return true
		end
	else
		g.grid = g.min_grid
		return true
	end
end

function grid:save(fname)
	local s = self
	local colmap = {
		[-1] = '-',
		[0] = '0',
		[1] = '1',
		[2] = '2',
		[3] = '3',
		[4] = '4',
		[5] = '5',
		[6] = '6',
		[7] = '7',
		[8] = '8',
		[9] = '9',
		[10] = 'a',
		[11] = 'b',
		[12] = 'c',
		[13] = 'd',
		[14] = 'e',
		[15] = 'f',
	}
	local y1,x1,y2,x2
	local cols = {}
	for y=1,s.max_grid do
		for x=1,s.max_grid do
			local c = s.pixels[y] and s.pixels[y][x] or -1
			if not cols[c] then
				cols[c] = c
			end
			if c ~= -1 then
				x1 = (not x1 or x1 > x) and x or x1
				x2 = (not x2 or x2 < x) and x or x2
				y1 = (not y1 or y1 > y) and y or y1
				y2 = (not y2 or y2 < y) and y or y2
			end
		end
	end
	if not x1 then
		return
	end
	local f, e = io.open(fname, "wb")
	if not f then
		return f, e
	end
	local p = ''
	for c=0,15 do
		if cols[c] then
			p = p .. colmap[c]
		else
			p = p .. '-'
		end
	end
	f:write(string.format("%s\n", p))
	dprint(p)
	for y=y1,y2 do
		local l = s.pixels[y] or {}
		local r = ''
		for x=x1,x2 do
			local c = l[x] or -1
			r = r .. colmap[c]
		end
		f:write(string.format("%s\n", r))
		dprint(r)
	end
	f:write("\n")
	f:close()
end

function grid:pos2cell(x, y)
	local s = self
	x = x - s.x
	y = y - s.y
	local dx = floor(self.w / s.grid)
	x = floor(x/dx) + 1
	y = floor(y/dx) + 1
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
	s.dirty = true
	return true
end

function grid:show()
	local s = self
	local dx = floor(self.w / s.grid)
	clear(s.x, s.y, s.w, s.h, 1)
	local Xd = spr.X:size()
	Xd = math.round((dx-Xd)/2)
	for y=1,s.grid do
		for x=1,s.grid do
			local c = s.pixels[y] and s.pixels[y][x]
			if not c or c == -1 then
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

local d, e = sprite_data(SPRITE)
if d then
	grid.pixels = d
end

function switch_ui()
	if pal.x == 0 then
		pal.x = w - pal.w
		title.x = w - title.w - 1
	else
		pal.x = 0
		title.x = 0
	end
end

function kbd(r, e)
	if r == 'text' then
		if e == '+' then
			grid:zoom(1)
		elseif e == '-' then
			grid:zoom(-1)
		end
	elseif r == 'keydown' then
		if e == 'tab' then
			switch_ui()
		elseif e == 'f2' then
			grid:save(SPRITE)
		end
	end
end

title:show()
switch_ui()

while true do
	fill(1)
	table.sort(obj, function(a, b) return a.lev > b.lev end)
	for _, v in ipairs(obj) do
		v:show()
	end
	table.sort(obj, function(a, b) return a.lev <= b.lev end)
	local r, e = input() -- todo
	kbd(r, e)
	local mx, my, mb = mouse()
	if mb.left or mb.right or mb.middle then
		for _, v in ipairs(obj) do
			local mx, my, mb = mouse()
			if mx >= v.x and my >= v.y and
				mx < v.x + v.w and
				my < v.y + v.h then
				if v:click(mx, my, mb, r == 'mousedown') then
					break
				end
			end
		end
	end
	flip(1/25)
end
