sys.title "sprited v0.01"
w, h = screen:size()
local floor = math.floor
local ceil = math.ceil
local spr = {}
local pan_mode

local SPRITE = ARGS[2] or 'sprite.spr'
spr.C = gfx.new [[
-------*
--*--
-----
*-*-*
-----
--*--
]]

spr.HL = gfx.new [[
--------89------
--------
-88--88-
-8----8-
---99---
---99---
-8----8-
-88--88-
--------
]]

spr.Hand = gfx.new [[
---------------f
--fff---
--ffff--
--ffff--
f-fffff-
fffffff-
fffffff-
-fffff--
--ffff--
]]

spr.X = gfx.new [[
*
*---*
-*-*-
--*--
-*-*-
*---*
]]

spr.G = gfx.new [[
--------------e-
--e--e--
--e--e--
eeeeeeee
--e--e--
--e--e--
eeeeeeee
--e--e--
--e--e--
]]

spr.S = gfx.new [[
------------c---
--------
-cc--cc-
-c----c-
--------
--------
-c----c-
-cc--cc-
--------
]]

pal = {
	x = 0;
	y = 0;
	cw = 8;
	ch = 8;
	w = 8*2;
	h = 8*8 + 16;
	color = 0;
	lev = -1;
}

function pal:select(x, y, c)
	x = self.x + x * 8
	y = self.y + y * 8
	screen:fill(x, y, 8, 8, c)
--	screen:poly({x, y,
--		x + 8 - 1,y,
--		x + 8 -1, y + 8 -1,
--		x, y + 8-1}, c)
end

local grid_mode = true
local sel_mode = false
local hand_mode = false
local hl_mode = false

function pal:show()
	local s = self
	local w = s.cw
	local h = s.ch
	local x, y = self.x, self.y
	for y=0, 7 do
		screen:clear(x, y*h, w, h, y)
		screen:clear(x+w, y*h, w, h, y+8)
	end
	local n = s.color
	local c = n + 7
	if c >= 16 then c = c - 16 end
	if n >= 8 then
		x = x + w
		n = n - 8
	end
	y = n
	screen:poly({x, y*h,
		x + w - 1, y*h,
		x + w -1, y*h + h - 1,
		x, y*h + h - 1}, c)
	if hand_mode then
		self:select(0, 8, 7)
	end
	if grid_mode then
		self:select(1, 8, 10)
	end
	if sel_mode then
		self:select(0, 9, 7)
	end
	if hl_mode then
		self:select(1, 9, 10)
	end
	spr.Hand:blend(screen, s.x, 8*8)
	spr.G:blend(screen, s.x + 8, 8*8)
	spr.S:blend(screen, s.x, 8*9)
	spr.HL:blend(screen, s.x + 8, 8*9)
end

function pal:pos2col(x, y)
	local s = self
	local w = s.cw
	local h = s.ch
	x = x - s.x
	y = y - s.y
	x = floor(x/w)
	y = floor(y/h)
	return x, y
end

function pal:click(x, y, mb, click)
	local x, y = self:pos2col(x, y)
	local c
	if y < 8 then
		c = x*8 + y
		self.color = c
	elseif y == 8 and x == 0 and click then -- hand mode
		hand_mode = not hand_mode
		sel_mode = false
	elseif y == 8 and x == 1 and click then -- grid mode
		grid_mode = not grid_mode
	elseif y == 9 and x == 0 and click then
		sel_mode = not sel_mode
		hand_mode = false
	elseif y == 9 and x == 1 and click then
		hl_mode = not hl_mode
	end
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
	max_grid = 128;
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
	local x, y = grid:pos2cell(input.mouse())
	local info = string.format("x%-3d %3d:%3d %s%s",
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
			if s.xoff ~= 0 and s.yoff ~= 0 then
				s:pan(s.grid/2, s.grid/2)
			end
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
	x1, y1 = 1, 1 -- no spaces!
	if s.sel_x1 then
		x1, y1, x2, y2 = s:getsel()
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
	if z.pixels then
		local i = 1
		for y = z.y1, z.y2 do
			s.pixels[y] = s.pixels[y] or {}
			for x = z.x1, z.x2 do
				s.pixels[y][x] = z.pixels[i]
				i = i + 1
			end
		end
		return
	end
	s.pixels[z.y][z.x] = z.val
	if n == 1 then
		s.dirty = false
	end
end

function grid:histadd(x1, y1, x2, y2)
	local s = self
	local b = {}
	for y = y1, y2 do
		s.pixels[y] = s.pixels[y] or {}
		for x = x1, x2 do
			table.insert(b, s.pixels[y][x] or -1)
		end
	end
	table.insert(s.history, { x1 = x1, y1 = y1,
		x2 = x2, y2 = y2, pixels = b })
end

function grid:fliph()
	local s = self
	local x1, y1, x2, y2 = s:getsel()
	if not x1 then
		return
	end

	local empty = s:isempty(x1, y1, x2, y2)
	if not empty then
		s:histadd(x1, y1, x2, y2)
	end

	local xc = x1 + floor((x2 - x1)/2)
	for y=y1,y2 do
		s.pixels[y] = s.pixels[y] or {}
		for x=x1,xc do
			local tmp = s.pixels[y][x]
			s.pixels[y][x] = s.pixels[y][x2-(x-x1)]
			s.pixels[y][x2-(x-x1)] = tmp
		end
	end
end

function grid:flipv()
	local s = self
	local x1, y1, x2, y2 = s:getsel()
	if not x1 then
		return
	end

	local empty = s:isempty(x1, y1, x2, y2)
	if not empty then
		s:histadd(x1, y1, x2, y2)
	end

	local yc = y1 + floor((y2 - y1)/2)
	for x=x1,x2 do
		for y=y1,yc do
			s.pixels[y] = s.pixels[y] or {}
			local tmp = s.pixels[y][x]
			s.pixels[y][x] = s.pixels[y2-(y-y1)][x]
			s.pixels[y2-(y-y1)][x] = tmp
		end
	end
end

function grid:paste()
	local s = self
	if not s.clipboard then
		return
	end
	local x, y = input.mouse()
	local tox, toy = s:pos2cell(x, y)
	s:histadd(tox, toy,
		tox + s.clipboard.w - 1,
		toy + s.clipboard.h - 1)
	for y=1, s.clipboard.h do
		s.pixels[toy+y-1] = s.pixels[toy+y-1] or {}
		for x=1,s.clipboard.w do
			s.pixels[toy+y-1][x+tox-1] = s.clipboard[y][x]
		end
	end
end

function grid:isempty(x1, y1, x2, y2)
	local s = self
	local col
	for y = y1, y2 do
		for x = x1, x2 do
			col = s.pixels[y] and s.pixels[y][x]
			if col and col ~= -1 then
				col = true
				break
			end
		end
	end
	return not col
end

function grid:cut(copy)
	local s = self
	local x1, y1, x2, y2 = s:getsel()
	if not x1 then
		return
	end
	s.clipboard = {}

	local empty = s:isempty(x1, y1, x2, y2)

	if not empty and not copy then
		s:histadd(x1, y1, x2, y2)
	end

	for y = y1, y2 do
		s.clipboard[y - y1 + 1] = {}
		s.pixels[y] = s.pixels[y] or {}
		for x = x1, x2 do
			s.clipboard[y - y1 + 1][x - x1 + 1] = s.pixels[y][x]
			if not copy then
				s.pixels[y][x] = -1
			end
		end
	end
	s.clipboard.w = x2 - x1 + 1
	s.clipboard.h = y2 - y1 + 1
	return true
end

function grid:click(x, y, mb, click)
	local s = self
	if pan_mode then
		return
	end
	x, y = s:pos2cell(x, y)
	if not x then
		return
	end
	if sel_mode then
		if click then
			if mb.right then
				self.sel_x1, self.sel_y1 = false, false
				return true
			end
			self.sel_x1, self.sel_y1 = x, y
			self.sel_x2, self.sel_y2 = x, y
			return true
		end
		self.sel_x2, self.sel_y2 = x, y
		return true
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
function grid:getsel()
	local s = self
	if not s.sel_x1 then
		return
	end
	local xmin = math.min(s.sel_x1, s.sel_x2)
	local ymin = math.min(s.sel_y1, s.sel_y2)
	local xmax = math.max(s.sel_x1, s.sel_x2)
	local ymax = math.max(s.sel_y1, s.sel_y2)
	return xmin, ymin, xmax, ymax
end
function grid:show()
	local s = self
	local mx, my = input.mouse()
	mx, my = s:pos2cell(mx, my)

	local dx = floor(self.w / s.grid)
	screen:clear(s.x, s.y, s.w, s.h, 1)
	local Xd = spr.X:size()
	Xd = math.round((dx-Xd)/2)
	for y=1,s.grid do
		for x=1,s.grid do
			local c = s.pixels[y+s.yoff] and s.pixels[y+s.yoff][x+s.xoff]
			if not c or c == -1 then
				screen:clear(s.x+(x-1)*dx, s.y+(y-1)*dx, dx, dx, { 0, 64, 48, 255})
				if s.grid < 128 then
					spr.X:blend(screen, s.x+(x-1)*dx + Xd, s.y+(y-1)*dx + Xd)
				end
			else
				screen:clear(s.x+(x-1)*dx, s.y+(y-1)*dx, dx, dx, c)
			end
			if hl_mode and  mx == s.xoff + x and my == s.yoff + y then
				c = (c or 0)+ 8
				if c >= 16 then c = 16 - c end
				c = { gfx.pal(c) }
				c[4] = 128
				screen:fill(s.x+(x-1)*dx, s.y+(y-1)*dx, dx, dx, c)
			end
		end
	end
	screen:poly({s.x, s.y,
		s.x + s.w, s.y,
		s.x+s.w, s.y+s.h,
		s.x, s.y+s.h}, 0)
	if s.grid < 128 then
		for x=1,s.grid do
			local colx = (((s.xoff + x - 1)%8 == 0) and grid_mode and 2) or 0
			local coly = (((s.yoff + x - 1)%8 == 0) and grid_mode and 2) or 0
			screen:line(s.x+(x-1)*dx, s.y, (x-1)*dx, s.y + s.h,
				colx)
			screen:line(s.x, s.y+(x-1)*dx, s.x+s.w, s.y+(x-1)*dx,
				coly)
		end
	end
	if grid.sel_x1 then
		local xmin, ymin, xmax, ymax = s:getsel()
		if xmax < s.xoff or ymax < s.yoff or xmin > s.xoff + s.grid or
			ymin > s.yoff + s.grid then
				return
		end
		local dx = floor(s.w / s.grid)
		xmin = xmin - 1
		ymin = ymin - 1
		screen:poly({(xmin - s.xoff)*dx, (ymin - s.yoff)*dx,
			(xmax - s.xoff)*dx, (ymin - s.yoff)*dx,
			(xmax - s.xoff)*dx, (ymax - s.yoff)*dx,
			(xmin - s.xoff)*dx, (ymax - s.yoff)*dx}, 7)
	end
end

local d, e = gfx.new(SPRITE, true) -- true - load data
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

function proc_inp(r, e, a, b, c, d)
	if r == 'mousewheel' then
		r = 'text'
		e = (e == -1) and '-' or '+'
	end
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
		if e == 'f1' then
			help_mode = not help_mode
		elseif e == 'tab' then
			switch_ui()
		elseif e == 'f2' then
			grid:save(SPRITE)
		elseif e == 'z' then
			grid:undo()
		elseif e == 'c' and input.keydown'ctrl' then
			grid:cut(true)
		elseif e == 'x' and input.keydown'ctrl' then
			grid:cut()
		elseif e == 'v' and input.keydown'ctrl' then
			grid:paste()
		elseif e == 'h' then
			grid:fliph()
		elseif e == 'v' then
			grid:flipv()
		end
	end
	if not pan_mode and (r == 'keydown' and  e == 'space' or
		r == 'mousedown' and hand_mode) then
		local ox, oy = input.mouse()
		local x, y = grid:pos()
		pan_mode =  { ox, oy, x, y }
	elseif pan_mode then
		local x, y, mb = input.mouse()
		local dd = grid.w / grid.grid
		local dx = floor((x - pan_mode[1])/dd)
		local dy = floor((y - pan_mode[2])/dd)
		grid:pos(pan_mode[3] - dx, pan_mode[4] - dy)
		if (not hand_mode and not input.keydown 'space') or (hand_mode and not mb.left) then
			pan_mode = nil
		end
	elseif input.keydown("right") then
		grid:pan(1, 0)
	elseif input.keydown("left") then
		grid:pan(-1, 0)
	elseif input.keydown("up") then
		grid:pan(0, -1)
	elseif input.keydown("down") then
		grid:pan(0, 1)
	end
	return r ~= nil
end

title:show()
switch_ui()
HELP = [[Keys:
z      - undo
ctrl-c - copy selection
ctrl-x - cut selection
ctrl-v - paste
h/v    - flip selection
cursor - pan
space  - pan (hold+mouse)
+/-    - zoom
tab    - change layout
lmb    - put pixel
rmb    - erase pixel
wheel  - zoom
lmb on [scale]    - zoom out
lmb on [filename] - save
mmb on [filename] - erase

Legend:
lmb - left mouse button
rmb - right mouse button
mmn - middle mouse button
[filename] - on the status line
[scale]    - on the status line
]]
while true do
	local r, v, a, b = sys.input()
	local mx, my, mb = input.mouse()
	if help_mode then
		screen:clear {0xff, 0xff, 0xe8, 0xff}
		if r == 'keydown' or r == 'mousedown' then
			help_mode = false
		end
		print(HELP)
		print("Here is the status line.", 0, h - 16, 0)
		screen:clear(0, h - 8, w, h - 8, 1)
		title:show()
	else
		proc_inp(r, v, a, b)
		if (mb.left or mb.right or mb.middle) then
			for _, v in ipairs(obj) do
				local mx, my, mb = input.mouse()
				if mx >= v.x and my >= v.y and
					mx < v.x + v.w and
					my < v.y + v.h then
					if v:click(mx, my, mb, r == 'mousedown') then
						break
					end
				end
			end
		end
		screen:clear(1)
		table.sort(obj, function(a, b) return a.lev > b.lev end)
		for _, v in ipairs(obj) do
			v:show()
		end
		table.sort(obj, function(a, b) return a.lev <= b.lev end)
	end
		gfx.flip(1, true) -- wait for event
end
