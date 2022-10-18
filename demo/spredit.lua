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
	xoff = 0;
	yoff = 0;
	grid = 16;
	max_grid = 64;
	min_grid = 16;
	lev = 1;
	pixels = {};
	history = { };
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
	local x, y = grid:pos2cell(mouse())
	local info = string.format("x%02d %2d:%2d %s%s",
		grid.grid, x-1, y-1, SPRITE, dirty)
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
		if mb.left then
			grid:save(SPRITE)
		elseif mb.middle then
			grid.pixels = {}
			grid.dirty = false
		end
	else
		if not grid:zoom(-1) then
			grid:zoom(0)
		end
	end
	return true
end

local obj = { pal, grid, title }

function grid:pan(dx, dy)
	self.xoff = self.xoff + dx
	self.yoff = self.yoff + dy
	if self.xoff < 0 then self.xoff = 0 end
	if self.yoff < 0 then self.yoff = 0 end
	if self.xoff > self.max_grid then self.xoff = self.max_grid end
	if self.yoff > self.max_grid then self.xoff = self.max_grid end
end

function grid:pos(x, y)
	if not x then
		return self.xoff, self.yoff
	end
	self.xoff = x
	self.yoff = y
	self:pan(0, 0)
end

function grid:zoom(inc)
	local s = self
	if inc > 0 then
		if s.grid > s.min_grid then
			s.grid = s.grid / 2
			s:pan(s.grid/2, s.grid/2)
			return true
		end
	elseif inc < 0 then
		if s.grid < s.max_grid then
			s:pan(-s.grid/2, -s.grid/2)
			s.grid = s.grid * 2
			return true
		end
	else
		s.grid = s.min_grid
		return true
	end
end

function grid:save(fname)
	local s = self
	local colmap = {
		[-1] = '-',
		[0] = '0', [1] = '1', [2] = '2', [3] = '3',
		[4] = '4', [5] = '5', [6] = '6', [7] = '7',
		[8] = '8', [9] = '9', [10] = 'a', [11] = 'b',
		[12] = 'c', [13] = 'd', [14] = 'e', [15] = 'f',
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
	s.dirty = false
end

function grid:pos2cell(x, y)
	local s = self
	x = x - s.x
	y = y - s.y
	local dx = floor(self.w / s.grid)
	x = floor(x/dx) + 1 + s.xoff
	y = floor(y/dx) + 1 + s.yoff
	return x, y
end

function grid:undo(x, y, mb)
	local s = self
	local n = #s.history
	if n < 1 then
		return
	end
	local z = table.remove(s.history, n)
	s.pixels[z.y][z.x] = z.val
	if n == 1 then
		s.dirty = false
	end
end

function grid:click(x, y, mb)
	local s = self
	x, y = s:pos2cell(x, y)
	if not x then
		return
	end
	s.pixels[y] = s.pixels[y] or {}
	local oval = s.pixels[y][x]
	local nval
	if mb.right then
		s.pixels[y][x] = nil
	else
		s.pixels[y][x] = pal.color
		nval = pal.color
	end
	if oval ~= nval then
		table.insert(s.history, { x = x, y = y, val = oval  })
		s.dirty = true
	end
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
			local c = s.pixels[y+s.yoff] and s.pixels[y+s.yoff][x+s.xoff]
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

local pan_mode

function proc_inp(r, e, a, b, c, d)
	if r == 'text' then
		if e == '+' then
			grid:zoom(1)
		elseif e == '-' then
			grid:zoom(-1)
		end
	elseif r == 'keyup' then
		if e == 'space' then
			pan_mode = nil
		end
	elseif r == 'keydown' then
		if e == 'tab' then
			switch_ui()
		elseif e == 'f2' then
			grid:save(SPRITE)
		elseif e == 'z' then
			grid:undo()
		elseif e == 'space' and not pan_mode then
			local ox, oy = mouse()
			local x, y = grid:pos()
			pan_mode =  { ox, oy, x, y }
		end
	end
	if pan_mode then
		local x, y = mouse()
		local dd = grid.w / grid.grid
		local dx = floor((x - pan_mode[1])/dd)
		local dy = floor((y - pan_mode[2])/dd)
		grid:pos(pan_mode[3] - dx, pan_mode[4] - dy)
		if not keydown 'space' then
			pan_mode = nil
		end
	elseif keydown("right") then
		grid:pan(1, 0)
	elseif keydown("left") then
		grid:pan(-1, 0)
	elseif keydown("up") then
		grid:pan(0, -1)
	elseif keydown("down") then
		grid:pan(0, 1)
	end
	return r ~= nil
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
	local r, v, a, b = input()
	proc_inp(r, v, a, b)
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
