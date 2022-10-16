local fps = 1/30;

local core = {}
local conf = {
	w = 512;
	h = 512;
	fg = { 0, 0, 0 };
	bg = { 0xff, 0xff, 0xe8 };
	font = "fonts/iosevka-regular.ttf",
	font_sz = 16,
}

local env = {
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
	if not env.win then
		return
	end
	x = x or 0
	y = y or 0
	local w, h = env.win:size()
	while text ~= '' do
		local s, e = text:find(" ", 1, true)
		if not s then s = text:len() end
		local word = text:sub(1, s)
		local p = core.font:text(word, col or conf.fg)
		local ww, hh = p:size()
		if x + ww >= w then
			x = 0
			y = y + hh
		end
		p:blend(env.win, x, y)
		x = x + ww
		text = text:sub(s + 1)
	end
end

function core.init()
	env.win = gfx.new(conf.w, conf.h)
	env.win:fill(conf.bg)
	core.font = gfx.font(DATADIR..'/'..conf.font, conf.font_sz * SCALE)
	if not core.font then
		core.err("Can't load font %q", DATADIR..'/'..conf.font)
		os.exit(1)
	end
	for k=2,#ARGS do
		local v = ARGS[k]
		local f, e = loadfile(v)
		if not f then
			core.err(e)
			return
		else
			core.fn = f
		end
		break
	end

	if not core.fn then
		core.err("No lua file")
		return
	end
	setfenv(core.fn, env)
	core.fn = coroutine.create(core.fn)
	-- system.window_mode 'fullscreen'
	-- system.window_mode 'normal'
end

function env.print(text, x, y, col)
	x = x or 0
	y = y or 0
	core.print(tostring(text),
		x * conf.font_sz * SCALE,
		y * conf.font_sz * SCALE, col)
end

function env.screen(w, h)
	env.win = gfx.new(w, h)
end

function env.fill(...)
	env.win:fill(...)
end

function env.flip()
	coroutine.yield()
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
		core.render(true)
		system.wait(left)
	end
end

local last_render = 0

function core.render(force)
	if not env.win then
		return
	end
	local start = system.time()
	if not force and start - last_render < fps then
		return
	end
	local ww, hh = gfx.win():size()
	local w, h = env.win:size()
	local xs, ys = ww/w, hh/h
	local scale = (xs <= ys) and xs or ys
	local dw = math.floor(w * scale)
	local dh = math.floor(h * scale)
	env.win:stretch(gfx.win(),
		math.floor((ww - dw)/2),
		math.floor((hh - dh)/2),
		dw, dh)
	gfx.flip()
	last_render = start
end

function core.run()
	while true do
		local e, v, a, b
		local start = system.time()
		e, v, a, b = system.poll()
		if e == 'quit' then
			break
		end
		core.render()
		if not core.err() and coroutine.status(core.fn) ~= 'dead' then
			local r, e = coroutine.resume(core.fn)
			if not r then
				core.err(e)
			end
		end
		local elapsed = system.time() - start
		system.wait(math.max(0, fps - elapsed))
	end
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
