local sprite = {
}

local spr = {}
spr.__index = spr

local function parse_line(l, pal)
	local r = { }
	for i=1,l:len() do
		local c = string.byte(l, i)
		c = string.char(c)
		c = pal[c or 0] or -1
		table.insert(r, c)
	end
	return r
end

function sprite.new(fname, pal)
	local s = { w = 0, h = 0, pal = {} }
	local f, e
	if type(fname) == 'string' then
		f, e = io.open(fname, "rb")
	else
		f = fname
	end
	if not f then
		return false, e
	end
	local nr = 1
	local data = false
	for l in f:lines() do
		l = l:gsub("\r", ""):gsub("^[ \t]+", ""):gsub("[ \t]$", "")
		if l:find("^[ \t]*$") or l:find("^;") then
			-- comment or empty
		elseif data then
			local r = parse_line(l, s.pal)
			if s.w < #r then
				s.w = #r
			end
			s.h = s.h + 1
			table.insert(s, r)
		else
			for i=1, l:len() do
				local c = string.byte(l, i)
				if c ~= string.byte '-' then
					s.pal[string.char(c)] = i - 1
				end
			end
			data = true
		end
		nr = nr + 1
	end
	if f ~= fname then
		f:close()
	end
	if not pal then
		return s
	end

	s.spr = gfx.new(s.w, s.h)
	for y=1, s.h do
		for x=1, s.w do
			local c = s[y][x]
			local col = pal[c] or { 0, 0, 0, 0 }
			s.spr:pixel(x - 1, y - 1, col) 
		end
	end
	return s.spr
end

return sprite
