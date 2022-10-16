local fps = 1/30;

local core = {}

function core.err(fmt, ...)
	if not fmt then
		return core.err_msg
	end
	local t = string.format(fmt, ...)
	core.err_msg = (core.err_msg or '') .. t
	return
end

function core.init()
	for k=2,#ARGS do
		local v = ARGS[k]
		local f, e = loadfile(v)
		if not f then
			core.err(e)
		else
			core.fn = f
		end
		break
	end
	if core.err() then
		print(core.err())
		os.exit(1)
	end
	if not core.fn then
		print("No lua file")
		os.exit(1)
	end
	-- system.window_mode 'fullscreen'
	-- system.window_mode 'normal'
end

local env = {
}

function env.screen(w, h)
	env.win = gfx.new(w, h)
	coroutine.yield()
end

function env.fill(...)
	env.win:fill(...)
end

function env.flip()
	coroutine.yield()
end

local last_render = 0

function core.run()
	setfenv(core.fn, env)
	core.fn = coroutine.create(core.fn)
	while true do
		local e, v, a, b
		local start = system.time()
		if system.time() - last_render > fps then
			gfx.flip()
			last_render = system.time()
		end
		e, v, a, b = system.poll()
		if e == 'quit' then
			break
		end
		coroutine.resume(core.fn)
		if env.win then
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
-- pixel(x, y, color) -- set pixel
-- copy(dst, x, y, w, h, tox, toy) -- dst is pixels
-- copy(dst, tox, toy) -- dst is pixels
-- blend(x, y, color) -- blend pixel
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
