local font = require "font"
local spr = require "spr"
local mixer = require "mixer"
local bit = require "bit"
local dump = require "dump"
local utf = require "utf"

local core

local input = {
	fifo = {};
	mouse = {
		btn = {};
	};
	kbd = {};
}
local conf = {
	fps = 1/50;
	w = 256;
	h = 256;
	fullscreen = false;
	pal = {
		[-1] = { 0, 0, 0, 0 }, -- transparent
		[0] = { 0, 0, 0, 0xff },
		[1] = { 0x1D, 0x2B, 0x53, 0xff },
		[2] = { 0x7E, 0x25, 0x53, 0xff },
		[3] = { 0x00, 0x87, 0x51, 0xff },
		[4] = { 0xAB, 0x52, 0x36, 0xff },
		[5] = { 0x5F, 0x57, 0x4F, 0xff },
		[6] = { 0xC2, 0xC3, 0xC7, 0xff },
		[7] = { 0xFF, 0xF1, 0xE8, 0xff },
		[8] = { 0xFF, 0x00, 0x4D, 0xff },
		[9] = { 0xFF, 0xA3, 0x00, 0xff },
		[10] = { 0xFF, 0xEC, 0x27, 0xff },
		[11] = { 0x00, 0xE4, 0x36, 0xff },
		[12] = { 0x29, 0xAD, 0xFF, 0xff },
		[13] = { 0x83, 0x76, 0x9C, 0xff },
		[14] = { 0xFF, 0x77, 0xA8, 0xff },
		[15] = { 0xFF, 0xCC, 0xAA, 0xff },
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
	bit = bit,
	string = string,
	pairs = pairs,
	ipairs = ipairs,
	io = io,
	tonumber = tonumber,
	tostring = tostring,
	coroutine = coroutine,
	utf = utf,
}

function thread.start(code)
	if type(code) ~= 'function' then
		error("Wrong argument", 2)
	end
	-- try to serialize it!
	local r, e = dump.new(code)
	if not r and e then -- error?
		core.err("Can not start thread.\n"..e)
	end
	code = string.format(
		"local f, e = require('dump').new [=========[\n%s"..
		"]=========]\n"..
		"if not f and e then\n"..
		"	error(e)\n"..
		"end\n"..
		"f()\n", r)
	local r, e, c = thread.new(code)
	if not r then
		local msg = string.format("%s\n%s", e, c)
		core.err(msg)
	end
	return r
end


local env_ro = {
	screen = gfx.new(conf.w, conf.h),
	thread = thread,
}

env_ro.__index = env_ro
env_ro.__newindex = function(t, nam, val)
	if rawget(env_ro, nam) then
		error("Can not change readonly value: "..nam, 2)
	end
	rawset(t, nam, val)
end

setmetatable(env, env_ro)

function env_ro.printf(x, y, col, fmt, ...)
	return env.print(string.format(fmt, ...), x, y, col)
end

function env_ro.time()
	return system.time()
end

function env_ro.fgcol(col)
	conf.fg = env.color(col) or conf.fg
end

function env_ro.bgcol(col)
	conf.bg = env.color(col) or conf.bg
end

function env_ro.pixel(o, x, y, ...)
	local col
	if type(o) == 'userdata' then
		col = env.color(...) or conf.fg
	else
		col = env.color(y, ...) or conf.fg
		x, y = o, x
		o = env.screen
	end
	return o:pixel(x, y, col)
end

function env_ro.fill(o, x, y, w, h, col)
	local col
	if type(o) ~= 'userdata' then
		x, y, w, h, col = o, x, y, w, h
		o = env.screen
	end
	if not y then
		col = env.color(x) or conf.fg
		return o:fill(col)
	end
	col = env.color(col) or conf.fg
	return o:fill(x, y, w, h, col)
end


function env_ro.blend(src, fx, fy, w, h, dst, x, y)
	if type(src) ~= 'userdata' then
		return
	end
	if type(w) == 'number' then
		return src:blend(fx, fy, w, h, dst, x, y)
	end
	if type(fx) == 'number' then
		x, y = fx, fy
		dst = env.screen
	else
		dst, x, y = fx, fy, w
	end
	src:blend(dst, x, y)
end

function env_ro.copy(src, fx, fy, w, h, dst, x, y)
	if type(src) ~= 'userdata' then
		return
	end
	if type(w) == 'number' then
		return src:copy(fx, fy, w, h, dst, x, y)
	end
	if type(fx) == 'number' then
		x, y = fx, fy
		dst = env.screen
	else
		dst, x, y = fx, fy, w
	end
	src:copy(dst, x, y)
end

function env_ro.clip(o, x1, y1, x2, y2)
	if type(o) == 'userdata' then
		return o:clip(x1, y1, x2, y2)
	end
	x1, y1, x2, y2 = o, x1, y1, x2
	return env.screen:clip(x1, y1, x2, y2)
end

function env_ro.noclip(o)
	if type(o) == 'userdata' then
		return o:noclip()
	end
	return env.screen:noclip()
end

function env_ro.offset(o, x, y)
	if type(o) == 'userdata' then
		return o:offset(x, y)
	end
	x, y = o, x
	return env.screen:offset(x, y)
end

function env_ro.noclip(o)
	if type(o) == 'userdata' then
		return o:noclip()
	end
	return env.screen:noclip()
end

function env_ro.line(o, x1, y1, x2, y2, col)
	local col
	if type(o) ~= 'userdata' then
		x1, y1, x2, y2, col = o, x1, y1, x2, y2
		o = env.screen
	end
	col = env.color(col) or conf.fg
	return o:line(x1, y1, x2, y2, col)
end

function env_ro.clear(o, x, y, w, h, col)
	local col
	if type(o) ~= 'userdata' then
		x, y, w, h, col = o, x, y, w, h
		o = env.screen
	end
	if not y then
		col = env.color(x) or conf.fg
		return o:clear(col)
	end
	col = env.color(col) or conf.fg
	return o:clear(x, y, w, h, col)
end

local last_flip = 0
local flips = {}
function env_ro.flip(fps, interrupt)
	core.render(true)
	local cur_time = env.time()
	env.sleep((fps or conf.fps) - (cur_time - last_flip), interrupt)
	last_flip = env.time()
	table.insert(flips, last_flip)
	if #flips > 50 then
		table.remove(flips, 1)
	end
	if #flips == 1 then
		return 0
	end
	return math.floor(#flips / math.abs(last_flip - flips[1]))
end

function env_ro.mouse()
	return input.mouse.x or 0, input.mouse.y or 0, input.mouse.btn
end

function env_ro.input()
	if #input.fifo == 0 then
		return
	end
	local v = table.remove(input.fifo, 1)
	return v.nam, table.unpack(v.args)
end

function env_ro.keydown(name)
	return input.kbd[name]
end

function env_ro.poly(o, vtx, col)
	if type(o) ~= 'userdata' then
		vtx, col = o, vtx
		o = env.screen
	end
	col = env.color(col) or conf.fg
	for i=1, #vtx-2,2 do
		o:line(vtx[i], vtx[i+1], vtx[i+2], vtx[i+3], col)
	end
	o:line(vtx[#vtx-1], vtx[#vtx], vtx[1], vtx[2], col)
end

function env_ro.color(k, r, g, b, a)
	if not k then
		return
	end
	if not r then
		if type(k) == 'table' then
			return k
		end
		return conf.pal[k]
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

function env_ro.sleep(to, interrupt)
	local start = system.time()
	repeat
		coroutine.yield()
		if interrupt and #input.fifo > 0 then
			break
		end
		local pass = system.time() - start
		local left = to - pass
		if left <= 0 then
			break
		end
		system.wait(left)
	until interrupt
end

function env_ro.dprint(...)
	local t = ''
	for k, v in ipairs({...}) do
		if t ~= '' then t = t .. ' ' end
		t = t .. tostring(v)
	end
	system.log(t)
end

function env_ro.error(text)
	env.screen:clear({0xff, 0xff, 0xe8})
	env.print(text, 0, 0, { 0, 0, 0})
	core.err_msg = text
	if not core.running() then
		return
	end
	coroutine.yield()
end

function env_ro.print(text, x, y, col)
	text = tostring(text)
	if not env.screen then
		system.log(text)
		return
	end
	x = x or 0
	y = y or 0
	col = env.color(col) or conf.fg

	text = text:gsub("\r", ""):gsub("\t", "    ")

	local w, h = env.screen:size()
	local ww, hh = env.font:size("")

	while text ~= '' do
		local s, e = text:find("[/:,. \n]", 1)
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
--[[
		if y > h - hh then -- vertical overflow
			local off = math.floor(y - (h - hh))
			env.screen:copy(0, off, w, h - off, env.win, 0, 0) -- scroll
			env.screen:clear(0, h - off, w, off, conf.bg)
			y = h - hh
		end
]]--
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

function env_ro.sprite_data(fname, y)
	if fname:find("\n") then
		return spr.new({ lines = function() return core.lines(fname) end })
	end
	return spr.new(fname)
end

function env_ro.sprite(x, y)
	local fname
	if type(x) == 'number' and type(y) == 'number' then
		return gfx.new(x, y)
	end
	if type(x) == 'string' then
		if x:find("\n") then
			return spr.new({ lines = function() return core.lines(x) end }, conf.pal)
		end
		if x:find("%.spr$") then
			return spr.new(x, conf.pal)
		end
	end
end

function env_ro.worker(fn)
	local f, e = coroutine.create(fn)
	if f then
		table.insert(core.fn, f)
	end
	return f, e
end

function env_ro.yield(...)
	return coroutine.yield(...)
end

env_ro.mixer = mixer

local api = { running = true }

function api.init(core_mod)
	env_ro.font = font.new(DATADIR..'/'..conf.font)
	core = core_mod
	if not env_ro.font then
		return false, string.format("Can't load font %q", DATADIR..'/'..conf.font)
	end
	env.worker(mixer.thread)
	return env
end

function api.event(e, v, a, b, c)
	if not api.running then
		return false
	end

	if e == 'quit' then
		api.running = false
		input.fifo  = {}
	end

	if e == 'mousemotion' then
		v, a = core.abs2rel(v, a)
	elseif e == 'mousedown' or e == 'mouseup' then
		a, b = core.abs2rel(a, b)
	end

	if (e == 'quit' or e == 'text' or e == 'keydown' or e == 'keyup' or
		e == 'mousedown' or e == 'mouseup' or e == 'mousewheel')
			and #input.fifo < 32 then
		local ev = { nam = e, args = { v, a, b, c } }
		table.insert(input.fifo, ev)
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
			conf.fullscreen = not conf.fullscreen
			if conf.fullscreen then
				system.window_mode 'fullscreen'
			else
				system.window_mode 'normal'
			end
		end
	elseif e == 'mousemotion' then
		input.mouse.x, input.mouse.y = v, a
	elseif e == 'mousedown' or e == 'mouseup' then
		input.mouse.btn[v] = (e == 'mousedown')
		input.mouse.x, input.mouse.y = a, b
	end
	return true
end

function api.done()
end

return api
