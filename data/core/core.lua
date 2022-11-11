local api = require "api"
require "std"
local env
local fps = 1/20 -- fallback, low fps

local core = {
  fn = {};
  view_x = 0;
  view_y = 0;
  suspended = {};
}

function core.go(fn, env)
  local f, e
  if type(fn) == 'string' then
    if fn:find("%.[lL][uU][aA]$") then
      f, e = loadfile(fn, "t", env)
    else
      f, e = loadfile(DATADIR.."/apps/"..fn..'.lua', "t", env)
    end
    if not f then
      core.err(e)
      return f, e
    end
  else
    f = fn
  end
  if setfenv and env then
    setfenv(f, env)
  end
  f, e = coroutine.create(f)
  if f then
    table.insert(core.fn, f)
  end
  return f, e
end

function core.stop(fn)
  if not fn then
    core.fn = {}
    return true
  end
  for k, f in ipairs(core.fn) do
    if f == fn then
      table.remove(core.fn, k)
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

function core.err(fmt, ...)
  if not fmt then
    if fmt == false then
      core.err_msg = false
      return
    end
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
  core.go(env.ARGS[1], env)
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
    if w <= 256 and h <= 256 then
      scale = math.floor(scale)
    else
      local oscale = scale
      scale = math.floor(scale)
      if scale + 0.5 < oscale then scale = scale + 0.5 end
    end
  end
  local dw = w * scale
  local dh = h * scale

  dw = math.floor(dw)
  dh = math.floor(dh)

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

  if #core.fn == 0 then
    if #core.suspended > 0 then
      local fn = table.remove(core.suspended, #core.suspended)
      table.insert(core.fn, fn)
      core.err(false)
    else
      return false
    end
  end

  if not core.err() then
    local i = 1
    while core.fn[i] do
      local fn = core.fn[i]
      if coroutine.status(fn) ~= 'dead' then
        local r, e = coroutine.resume(fn)
        if not r then
          e = e .. '\n'..debug.traceback(fn)
          core.err(e)
          break
        elseif e == 'suspend' then
          table.insert(core.suspended, fn)
          table.remove(core.fn, i)
        else
          i = i + 1
        end
      else
        table.remove(core.fn, i)
      end
    end
  end

  if core.render() then
    sys.sleep(fps)
  end
  return true
end

return core
