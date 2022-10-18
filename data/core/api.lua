local font = require "font"
local core
local input = {
	fifo = {};
	mouse = {
		btn = {};
	};
	kbd = {};
}
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

local env = {
	table = table,
	math = math,
	string = string,
	pairs = pairs,
	ipairs = ipairs,
}

local env_ro = {
	screen = gfx.new(conf.w, conf.h)
}

env_ro.__index = env_ro
env_ro.__newindex = function(t, nam, val)
	if rawget(env_ro, nam) then
		error("Can not change readonly value: "..nam, 2)
	end
	rawset(t, nam, val)
end

setmetatable(env, env_ro)

function env.printf(x, y, col, fmt, ...)
	return env.print(string.format(fmt, ...), x, y, col)
end

function env.time()
	return system.time()
end

function env.fg(col)
	conf.fg = conf.pal[col] or conf.fg
end

function env.bg(col)
	conf.bg = conf.pal[col] or conf.bg
end

function env.pixel(x, y, col)
	col = conf.pal[col] or conf.fg
	return env.screen:pixel(x, y, col)
end

function env.fill(x, y, w, h, col)
	if not y then
		col = conf.pal[x] or conf.bg
		return env.screen:fill(col)
	end
	col = conf.pal[col] or conf.bg
	return env.screen:fill(x, y, w, h, col)
end

function env.clear(x, y, w, h, col)
	if not y then
		col = conf.pal[x] or conf.bg
		return env.screen:clear(col)
	end
	col = conf.pal[col] or conf.bg
	return env.screen:clear(x, y, w, h, col)
end

local last_flip = 0

function env.flip(fps)
	core.render(true)
	env.sleep((fps or conf.fps) - (env.time() - last_flip))
	last_flip = env.time()
end

function env.mouse()
	return input.mouse.x or 0, input.mouse.y or 0, input.mouse.btn
end

function env.input()
	if #input.fifo == 0 then
		return
	end
	local v = table.remove(input.fifo, 1)
	return v[1], v.sym
end

function env.color(k, r, g, b, a)
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

function env.sleep(to)
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

function env.error(text)
	env.screen:clear({0xff, 0xff, 0xe8})
	env.print(text, 0, 0, { 0, 0, 0})
	core.err_msg = text
	if coroutine.running() then
		coroutine.yield()
	end
end

function env.print(text, x, y, col)
	if not env.screen then
		system.log(text)
		return
	end
	text = text:gsub("\r", ""):gsub("\t", "    ")
	x = x or 0
	y = y or 0
	col = col or conf.fg
	local w, h = env.screen:size()
	local ww, hh = env.font:size("")
	while text ~= '' do
		local s, e = text:find("[ \n]", 1)
		if not s then s = text:len() end
		local nl = text:sub(s, s) == '\n'
		local word = text:sub(1, s):gsub("\n$", "")
		local p = env.font:text(word, col)
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
			env.screen:copy(0, off, w, h - off, env.win, 0, 0) -- scroll
			env.screen:clear(0, h - off, w, off, conf.bg)
			y = h - hh
		end
		if p then
			p:blend(env.screen, x, y)
		end
		x = x + ww
		text = text:sub(s + 1)
		if nl then
			x = 0
			y = y + hh
		end
	end
end

local api = {
}

function api.init(c)
	env_ro.font = font.new(DATADIR..'/'..conf.font)
	core = c
--	 gfx.font(DATADIR..'/'..conf.font, math.floor(conf.font_sz))
	if not env_ro.font then
		return false, string.format("Can't load font %q", DATADIR..'/'..conf.font)
	end
	return env
end

function api.event(e, v, a, b)
	if (e == 'text' or e == 'keydown') and #input.fifo < 16 then
		table.insert(input.fifo,
			{ sym = (e == 'text' and v or false), v })
	end
	if e == 'keyup' then
		if v:find("alt$") then
			input.kbd.alt = false
		end
		input.kbd[v] = false
	elseif e == 'keydown' then
		if v:find("alt$") then
			input.kbd.alt = true
		end
		input.kbd[v] = true
		if v == 'return' and input.kbd.alt then
			core.fullscreen = not core.fullscreen
			if core.fullscreen then
				system.window_mode 'fullscreen'
			else
				system.window_mode 'normal'
			end
		end
	elseif e == 'mousemotion' then
		input.mouse.x, input.mouse.y = core.abs2rel(v, a)
	elseif e == 'mousedown' or e == 'mouseup' then
		input.mouse.btn[v] = (e == 'mousedown')
		input.mouse.x, input.mouse.y = core.abs2rel(a, b)
	end
end

function api.done()
end

return api
