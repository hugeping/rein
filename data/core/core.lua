local font = require "font"

local fps = 1/30;

math.round = function(num, n)
	local m = 10 ^ (n or 0)
	return math.floor(num * m + 0.5) / m
end

local core = {
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
	input = {};
	kbd = {};
	view_x = 0;
	view_y = 0;
	mouse_btn = {};
}

local conf = {
	w = 256;
	h = 256;
	fg = { 0, 0, 0 };
	bg = { 0xff, 0xff, 0xe8 };
	font = "fonts/8x8.fnt",
--	font_sz = 16,
}

local env = {
	table = table,
	math = math,
	string = string,
	pairs = pairs,
	ipairs = ipairs,
}

function core.err(fmt, ...)
	if not fmt then
		return core.err_msg
	end
	local t = string.format(fmt, ...)
	core.err_msg = (core.err_msg or '') .. t
	system.log(t)
	core.print(t)
	return
end

function core.print(text, x, y, col)
	if not core.win then
		return
	end
	text = text:gsub("\r", "")
	x = x or 0
	y = y or 0
	local w, h = core.win:size()
	local ww, hh = core.font:size("")
	while text ~= '' do
		local s, e = text:find("[ \n]", 1)
		if not s then s = text:len() end
		local nl = text:sub(s, s) == '\n'
		local word = text:sub(1, s):gsub("\n$", "")
		local p = core.font:text(word, col or conf.fg)
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
			core.win:copy(0, off, w, h - off, env.win, 0, 0) -- scroll
			core.win:clear(0, h - off, w, off, conf.bg)
			y = h - hh
		end
		if p then
			p:blend(core.win, x, y)
		end
		x = x + ww
		text = text:sub(s + 1)
		if nl then
			x = 0
			y = y + hh
		end
	end
end

function core.init()
	core.win = gfx.new(conf.w, conf.h)
	core.win:fill(conf.bg)
	core.font = font.new(DATADIR..'/'..conf.font)
--	 gfx.font(DATADIR..'/'..conf.font,
--		math.floor(conf.font_sz))
	if not core.font then
		core.err("Can't load font %q", DATADIR..'/'..conf.font)
		os.exit(1)
	end
	local f, e
	for k=2,#ARGS do
		local v = ARGS[k]
		f, e = loadfile(v, "t", env)
		if not f then
			core.err(e)
			return
		end
		break
	end

	if not f then
		core.err("No lua file")
		return
	end
	if setefenv then
		setfenv(f, env)
	end
	core.fn = coroutine.create(f)
	-- system.window_mode 'fullscreen'
	-- system.window_mode 'normal'
end

function core.done()
end

function env.print(text, x, y, col)
	x = x or 0
	y = y or 0
	core.print(tostring(text), x, y, col)
end

function env.printf(x, y, fmt, ...)
	return env.print(string.format(fmt, ...), x, y)
end

function env.time()
	return system.time()
end

function env.screen(w, h)
	core.win = gfx.new(w, h)
end

function env.fg(col)
	conf.fg = core.pal[col] or conf.fg
end

function env.bg(col)
	conf.bg = core.pal[col] or conf.bg
end

function env.pixel(x, y, col)
	col = core.pal[col] or conf.fg
	return core.win:pixel(x, y, col)
end

function env.fill(x, y, w, h, col)
	if not y then
		col = core.pal[x] or conf.bg
		return core.win:fill(col)
	end
	col = core.pal[col] or conf.bg
	return core.win:fill(x, y, w, h, col)
end

function env.clear(x, y, w, h, col)
	if not y then
		col = core.pal[x] or conf.bg
		return core.win:clear(col)
	end
	col = core.pal[col] or conf.bg
	return core.win:clear(x, y, w, h, col)
end

local last_flip = 0

function env.flip(fps)
	core.render(true)
	env.sleep((fps or conf.fps) - (env.time() - last_flip))
	last_flip = env.time()
end

function env.mouse()
	return core.mouse_x or 0, core.mouse_y or 0, core.mouse_btn
end

function env.input()
	if #core.input == 0 then
		return
	end
	local v = table.remove(core.input, 1)
	return v[1], v.sym
end

function env.pal(t)
	if not t then
		return core.pal
	end
	if type(t) == 'table' then
		core.pal = t
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

local last_render = 0

function core.render(force)
	if not core.win then
		return
	end
	local start = system.time()
	if not force and start - last_render < fps then
		return
	end
	local ww, hh = gfx.win():size()
	local w, h = core.win:size()
	local xs, ys = ww/w, hh/h
	local scale = (xs <= ys) and xs or ys
	if scale > 1.0 then
		scale = math.floor(scale)
	end
	local dw = math.floor(w * scale)
	local dh = math.floor(h * scale)
	core.view_w, core.view_h = dw, dh
	core.view_x, core.view_y = math.floor((ww - dw)/2), math.floor((hh - dh)/2)
	core.win:stretch(gfx.win(),
		core.view_x, core.view_y,
		core.view_w, core.view_h)
	gfx.flip()
	last_render = start
end

function core.abs2rel(x, y)
	local w, h = core.win:size()
	if not core.view_w or
		core.view_w == 0 or
		core.view_h == 0 then
		return 0, 0
	end
	x = math.round((x - core.view_x) * w / core.view_w)
	y = math.round((y - core.view_y) * h / core.view_h)
	return x, y
end

function core.run()
	local e, v, a, b
	-- local start = system.time()
	e, v, a, b = system.poll()

	if (e == 'text' or e == 'keydown') and #core.input < 16 then
		table.insert(core.input,
			{ sym = (e == 'text' and v or false), v })
	end

	if e == 'quit' then
		return false
	elseif e == 'keyup' then
		if v:find("alt$") then
			core.kbd.alt = false
		end
		core.kbd[v] = false
	elseif e == 'keydown' then
		if v:find("alt$") then
			core.kbd.alt = true
		end
		core.kbd[v] = true
		if v == 'return' and core.kbd.alt then
			core.fullscreen = not core.fullscreen
			if core.fullscreen then
				system.window_mode 'fullscreen'
			else
				system.window_mode 'normal'
			end
		end
	elseif e == 'mousemotion' then
		core.mouse_x, core.mouse_y = core.abs2rel(v, a)
	elseif e == 'mousedown' or e == 'mouseup' then
		core.mouse_btn[v] = (e == 'mousedown')
		core.mouse_x, core.mouse_y = core.abs2rel(a, b)
	end
	-- core.render()
	if not core.err() and coroutine.status(core.fn) ~= 'dead' then
		local r, e = coroutine.resume(core.fn)
		if not r then
			core.err(e)
		end
	else
		core.render()
	end
	return true
end

return core

-- ARGS -- arguments
-- SCALE -- dpi scale 

-- color: { r, g, b, a }

-- gfx.
-- win() -- return win pixels, invalidate after resize
-- flip() -- copy backbuffer
-- new(w, h) -- create empty pixels
-- new(file) -- create pixels from image-file
-- icon(pixels) -- set icon app
-- font(file) -- load font

-- font:
-- text(text, color) -- create pixels with rendered text
-- size(text) -- return w, h of text (no render needed)

-- pixels:
-- size() -- returns w, h
-- fill(x, y, w, h, color)
-- fill(color)
-- scale(xs[, ys]) -- scale pixels, return new pixels
-- clear(x, t, w, h, color) -- like fill, but w/o alpha. fast
-- clear(color)
-- val(x, y) -- returns r, g, b, a
-- pixel(x, y, color) -- set/blend pixel
-- copy(dst, x, y, w, h, tox, toy) -- dst is pixels
-- copy(dst, tox, toy) -- dst is pixels
-- blend() -- as copy but with blending
-- line(x1, y1, x2, y2, color)
-- lineAA(x1, y1, x2, y2, color)
-- fill_trinagle(x1, y1, x2, y2, x3, y3, color)
-- circle(x, y, r, color)
-- circleAA(x, y, r, color)
-- fill_circle(x, y, r, color)
-- fill_poly({vertex}, color)

-- system.
--  log(text) -- log message
--  time() -- get ticks from start
--  sleep(to)
--  wait(to) -- wait event or timeout
--  poll() -- peek new events
--  events:
--    quit - close app
--    exposed -- showed win
--    resize w h -- win resized
--    keydown key
--    keyup key
--    text text
--    mousedown btn x y clicks
--    mouseup btn
--    mousemotion x y xrel yrel
--    mousewheel off
-- title(title) -- window title
-- window_mode(m) m = normal, maximized, fullscreen
-- chdir(dir)
-- mkdir(dir)
-- readdir()
-- utf_next
-- utf_prev
-- utf_len
-- utf_sym
