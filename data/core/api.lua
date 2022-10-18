local font = require "font"
local core
local conf = {
	w = 256;
	h = 256;
	pal = {
		[0] = { 0, 0, 0 },
		[1] = { 0x1D, 0x2B, 0x53 },
		[2] = { 0x7E, 0x25, 0x53 },
		[3] = { 0x00, 0x87, 0x51 },
		[4] = { 0xAB, 0x52, 0x36 },
		[5] = { 0x5F, 0x57, 0x4F },
		[6] = { 0xC2, 0xC3, 0xC7 },
		[7] = { 0xFF, 0xF1, 0xE8 },
		[8] = { 0xFF, 0x00, 0x4D },
		[9] = { 0xFF, 0xA3, 0x00 },
		[10] = { 0xFF, 0xEC, 0x27 },
		[11] = { 0x00, 0xE4, 0x36 },
		[12] = { 0x29, 0xAD, 0xFF },
		[13] = { 0x83, 0x76, 0x9C },
		[14] = { 0xFF, 0x77, 0xA8 },
		[15] = { 0xFF, 0xCC, 0xAA },
	};
	fg = { 0, 0, 0 };
	bg = { 0xff, 0xff, 0xe8 };
	font = "fonts/8x8.fnt",
}

local res = {

}

local api = {
	table = table,
	math = math,
	string = string,
	pairs = pairs,
	ipairs = ipairs,
}

local ro_api = {
	screen = gfx.new(conf.w, conf.h)
}

ro_api.__index = ro_api
ro_api.__newindex = function(t, nam, val)
	if rawget(ro_api, nam) then
		error("Can not change readonly value: "..nam, 2)
	end
	rawset(t, nam, val)
end

setmetatable(api, ro_api)

function api.printf(x, y, col, fmt, ...)
	return api.print(string.format(fmt, ...), x, y, col)
end

function api.time()
	return system.time()
end

function api.fg(col)
	conf.fg = conf.pal[col] or conf.fg
end

function api.bg(col)
	conf.bg = conf.pal[col] or conf.bg
end

function api.pixel(x, y, col)
	col = conf.pal[col] or conf.fg
	return api.screen:pixel(x, y, col)
end

function api.fill(x, y, w, h, col)
	if not y then
		col = conf.pal[x] or conf.bg
		return api.screen:fill(col)
	end
	col = conf.pal[col] or conf.bg
	return api.screen:fill(x, y, w, h, col)
end

function api.clear(x, y, w, h, col)
	if not y then
		col = conf.pal[x] or conf.bg
		return api.screen:clear(col)
	end
	col = conf.pal[col] or conf.bg
	return api.screen:clear(x, y, w, h, col)
end

local last_flip = 0

function api.flip(fps)
	core.render(true)
	api.sleep((fps or conf.fps) - (api.time() - last_flip))
	last_flip = api.time()
end

function api.mouse()
	return core.mouse_x or 0, core.mouse_y or 0, core.mouse_btn
end

function api.input()
	if #core.input == 0 then
		return
	end
	local v = table.remove(core.input, 1)
	return v[1], v.sym
end

function api.color(k, r, g, b, a)
	if not k then
		return
	end
	if not r then
		return conf.pal[k] or conf.pal[0]
	end
	if r == false then
		conf.pal[k] = nil
		return
	end
	if type(r) == 'table' then
		conf.pal[k] = r
		return
	end
	if type(r) == 'number' then
		conf.pal[k] = { r, g, b, a }
		return
	end
end

function api.sleep(to)
	local start = system.time()
	while true do
		coroutine.yield()
		local pass = system.time() - start
		local left = to - pass
		if left <= 0 then
			break
		end
--		core.render(true)
		system.wait(left)
	end
end

function api.error(text)
	api.screen:clear({0xff, 0xff, 0xe8})
	api.print(text, 0, 0, { 0, 0, 0})
	core.err_msg = text
	if coroutine.running() then
		coroutine.yield()
	end
end

function api.print(text, x, y, col)
	if not api.screen then
		system.log(text)
		return
	end
	text = text:gsub("\r", ""):gsub("\t", "    ")
	x = x or 0
	y = y or 0
	col = col or conf.fg
	local w, h = api.screen:size()
	local ww, hh = res.font:size("")
	while text ~= '' do
		local s, e = text:find("[ \n]", 1)
		if not s then s = text:len() end
		local nl = text:sub(s, s) == '\n'
		local word = text:sub(1, s):gsub("\n$", "")
		local p = res.font:text(word, col)
		if p then
			ww, hh = p:size()
		else
			ww = 0
		end
		if x + ww >= w then
			x = 0
			y = y + hh
		end
		if y > h - hh then -- vertical overflow
			local off = math.floor(y - (h - hh))
			api.screen:copy(0, off, w, h - off, env.win, 0, 0) -- scroll
			api.screen:clear(0, h - off, w, off, conf.bg)
			y = h - hh
		end
		if p then
			p:blend(api.screen, x, y)
		end
		x = x + ww
		text = text:sub(s + 1)
		if nl then
			x = 0
			y = y + hh
		end
	end
end

return {
	init = function(c)
		res.font = font.new(DATADIR..'/'..conf.font)
		core = c
--	 gfx.font(DATADIR..'/'..conf.font, math.floor(conf.font_sz))
		if not res.font then
			return false, string.format("Can't load font %q", DATADIR..'/'..conf.font)
		end
		return api
	end
}
