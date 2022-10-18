local font = require "font"
local api = require "api"

local env
local fps = 1/30;

math.round = function(num, n)
	local m = 10 ^ (n or 0)
	return math.floor(num * m + 0.5) / m
end

local core = {
	view_x = 0;
	view_y = 0;
}

function core.err(fmt, ...)
	if not fmt then
		return core.err_msg
	end
	local t = string.format(fmt, ...)
	core.err_msg = (core.err_msg or '') .. t
	system.log(t)
	if env.error then
		env.error(t)
	end
	return
end

function core.init()
	local err
	env, err = api.init(core)
	if not env then
		core.err(err)
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

local last_render = 0

function core.render(force)
	if not env.screen then
		return
	end
	local start = system.time()
	if not force and start - last_render < fps then
		return
	end
	local ww, hh = gfx.win():size()
	local w, h = env.screen:size()
	local xs, ys = ww/w, hh/h
	local scale = (xs <= ys) and xs or ys
	if scale > 1.0 then
		scale = math.floor(scale)
	end
	local dw = math.floor(w * scale)
	local dh = math.floor(h * scale)
	core.view_w, core.view_h = dw, dh
	core.view_x, core.view_y = math.floor((ww - dw)/2), math.floor((hh - dh)/2)
	env.screen:stretch(gfx.win(),
		core.view_x, core.view_y,
		core.view_w, core.view_h)
	gfx.flip()
	last_render = start
end

function core.abs2rel(x, y)
	local w, h = env.screen:size()
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

	if e == 'quit' then
		return false
	else
		api.event(e, v, a, b)
	end

	-- core.render()
	if not core.err() and coroutine.status(core.fn) ~= 'dead' then
		local r, e = coroutine.resume(core.fn)
		if not r then
			e = e .. '\n'..debug.traceback(core.fn)
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
