local api = require "api"

local env
local fps = 1/20 -- fallback, low fps

math.round = function(num, n)
	local m = 10 ^ (n or 0)
	return math.floor(num * m + 0.5) / m
end

function string.strip(str)
	if not str then return str end
	str = str:gsub("^[ \t]+",""):gsub("[ \t]+$","")
	return str
end

function string.split(s, sep_arg)
	local sep, fields = sep_arg or " ", {}
	local pattern = string.format("([^%s]+)", sep)
	s:gsub(pattern, function(c) table.insert(fields, string.strip(c)) end)
	return fields
end


if not table.unpack then
	table.unpack = unpack
end

local core = {
	fn = {};
	view_x = 0;
	view_y = 0;
}

function core.go(fn)
	local f, e = coroutine.create(fn)
	if f then
		table.insert(core.fn, f)
	end
	return f, e
end

function core.stop(fn)
	for k, f in ipairs(core.fn) do
		if f == fn then
			table.remove(core.fn[k])
			return true
		end
	end
end

function core.running()
	if _VERSION == "Lua 5.1" then
		return coroutine.running()
	end
	local _, v = coroutine.running()
	return not v
end

function core.lines(text)
	text = text:gsub("\r", "")
	local state = {text, 1, 1}
	local function next_line()
		local text, begin, line_n = state[1], state[2], state[3]
		if begin < 0 then
			return nil
		end
		state[3] = line_n + 1
		local b, e = text:find("\n", begin, true)
		if b then
			state[2] = e+1
			return text:sub(begin, e-1), line_n
		else
			state[2] = -1
			return text:sub(begin), line_n
		end
	end
	return next_line
end

function core.err(fmt, ...)
	if not fmt then
		return core.err_msg
	end
	local t = string.format(fmt, ...)
	core.err_msg = (core.err_msg or '') .. t
	sys.log(t)
	if env.error then
		env.error(t)
	end
	return
end

function core.init()
	gfx.icon(gfx.new(DATADIR..'/icon.png'))
	local err
	env, err = api.init(core)
	if not env then
		core.err(err)
		os.exit(1)
	end
	env.ARGS = {}
	local f, e, optarg
	for k=2,#ARGS do
		local v = ARGS[k]
		if v:find("-", 1, true) == 1 then
			-- todo options
		else -- file to run
			optarg = k
			break
		end
	end
	if optarg then
		for i=optarg,#ARGS do
			table.insert(env.ARGS, ARGS[i])
		end
	else
		env.ARGS[1] = DATADIR..'/boot.lua'
	end
	f, e = loadfile(env.ARGS[1], "t", env)
	if not f then
		core.err(e)
		return
	end

	if not f then
		core.err("No lua file")
		return
	end
	if setfenv then
		setfenv(f, env)
	end
	table.insert(core.fn, coroutine.create(f))
	-- sys.window_mode 'fullscreen'
	-- sys.window_mode 'normal'
end

function core.done()
	api.done()
end

local last_render = 0

function core.render(force)
	if not env.screen then
		return
	end
	local start = sys.time()
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
	local dw = w * scale
	local dh = h * scale

	if w <= 256 and h <= 256 then
		dw = math.floor(dw)
		dh = math.floor(dh)
	end

	core.view_w, core.view_h = dw, dh
	core.view_x, core.view_y = math.floor((ww - dw)/2), math.floor((hh - dh)/2)

	local win = gfx.win()
	win:clip(core.view_x, core.view_y,
		core.view_x + core.view_w,
		core.view_y + core.view_h)
	env.screen:stretch(win,
		core.view_x, core.view_y,
		core.view_w, core.view_h)
	gfx.flip()
	last_render = start
	return true
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
	if not api.event(sys.poll()) then
		return false
	end

	-- core.render()
	if not core.err() then
		local i = 1
		local n = #core.fn
		while i <= n do
			local fn = core.fn[i]
			if coroutine.status(fn) ~= 'dead' then
				local r, e = coroutine.resume(fn)
				if not r then
					e = e .. '\n'..debug.traceback(fn)
					core.err(e)
					break
				end
				i = i + 1
			else
				table.remove(core.fn, i)
				n = n - 1
			end
		end
	end
	if core.render() then
		sys.sleep(fps)
	end
	return true
end

return core
