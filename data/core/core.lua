local api = require "api"
require "std"
local env
local fps = 1/20 -- fallback, low fps

local core = {
  fn = {};
  view_x = 0;
  view_y = 0;
  suspended = {};
  scale = false;
  apps = {};
}

function core.getopt(args, ops)
  local optarg = #args + 1
  local ret = {}
  for k, v in pairs(ops) do
    if type(v) ~= 'boolean' then
      ret[k] = ops[k]
    end
  end
  local i = 1
  while i < #args do
    i = i + 1
    local v = args[i]
    if not v:startswith('-') or v:len() == 1 then
      optarg = i
      break
    end
    if v == "--" then
      optarg = i + 1
      break
    end
    local o = ops[v:sub(2)]
    if o == nil then
      print("Unknown option: "..v)
    elseif o ~= true then
      if i == #args then
        print("No argument: "..v)
        break
      end
      i = i + 1
      ret[v:sub(2)] = args[i]
    else
      ret[v:sub(2)] = o
    end
  end
--  if optarg > #args then optarg = false end
  return ret, optarg
end

function core.go(fn, env)
  local f, e
  if type(fn) == 'string' then
    if core.apps[fn] then
      f, e = loadfile(core.apps[fn], "t", env)
    else
      f, e = loadfile(fn, "t", env)
    end
    if not f then
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
  local r, v = coroutine.running()
  if v == nil then
    return coroutine.running()
  end
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
  io.stdout:setvbuf "no"
  io.stderr:setvbuf "no"
  gfx.icon(gfx.new(DATADIR..'/icon.png'))
  local err
  env, err = api.init(core)
  if not env then
    core.err(err)
    os.exit(1)
  end

  for _, v in ipairs(sys.readdir(DATADIR..'/apps/')) do
    if v:find("%.[lL][uU][aA]$") then
      local key = v:lower():gsub("%.[lL][uU][aA]$", "")
      core.apps[key] = DATADIR..'/apps/'..v
    end
  end

  env.ARGS = {}
  local opts, optarg = core.getopt(ARGS, {
    s = true,
    nosound = true,
    vpad = true,
    fs = true,
  })
  core.fullscreen = opts.fs
  if core.fullscreen then
    sys.window_mode 'fullscreen'
  end
  core.scale = opts.s
  core.nosound = opts.nosound
  core.vpad_enabled = opts.vpad
  if optarg <= #ARGS then
    for i=optarg,#ARGS do
      table.insert(env.ARGS, ARGS[i])
    end
  else
    env.ARGS[1] = DATADIR..'/boot.lua'
  end
  local r, e = core.go(env.ARGS[1], env)
  if not r then
    core.err(e)
  end
  -- sys.window_mode 'fullscreen'
  -- sys.window_mode 'normal'
end

function core.done()
  api.done()
end

local last_render = 0

local vpad = { fingers = {} }
local vpad_col = { 192, 192, 192, 255 }
function core.vpad(x, y, w, h)
  if vpad.x == x and vpad.y == y and
    vpad.w == w and vpad.h == h then
    return
  end
  local win = gfx.win()
  win:clear(x, y, w, h, { 0, 0, 0, 255 })
  vpad.x, vpad.y, vpad.w, vpad.h = x, y, w, h
  local xc = w/4 + x
  local yc = h/2 + y
  local r = h/4 < w/4 and h/4 or w/4
  vpad.stick = { x = xc, y = yc, r = r }
  win:circle(xc, yc, r, {255, 255, 255 })
  local d = r/4
  win:circle(xc, yc, r / 2, vpad_col)
  r = r * 0.9
  win:fill_poly( {xc, yc - r, xc + d, yc - r + d, xc - d, yc - r + d }, vpad_col)
  win:fill_poly( {xc, yc + r, xc + d, yc + r - d, xc - d, yc + r - d }, vpad_col)
  win:fill_poly( {xc - r, yc, xc - r + d, yc - d, xc - r + d, yc + d }, vpad_col)
  win:fill_poly( {xc + r, yc, xc + r - d, yc - d, xc + r - d, yc + d }, vpad_col)
  r = h/8 < w/8 and h/8 or w/8
  xc = x + 7*w/8
  yc = y + h/2 - r
  vpad.z = { x = xc, y = yc, r = r }
  win:circle(xc, yc, r, vpad_col)
  win:circle(xc, yc, r/2, vpad_col)
  xc = x + 6*w/8
  yc = y + h/2 + r
  vpad.x = { x = xc, y = yc, r = r }
  win:circle(xc, yc, r, vpad_col)
  win:rect(xc - r/2, yc - r/2, xc + r/2, yc + r/2, vpad_col)
  r = r / 2
  xc = x + w - 1.5*r
  yc = y + h - 1.5*r
  vpad.escape = { x = xc, y = yc, r = r }
  win:circle(xc, yc, r, vpad_col)
  win:rect(xc - r/1.5, yc - r/4, xc + r/1.5, yc + r/4, vpad_col)
end

local function finger_process(old, new)
  for k, v in pairs(old) do -- keyup old keys
    if v and not new[k] then
      old[k] = false
      if not api.event("keyup", k) then return false end
    end
  end
  for k, _ in pairs(new) do -- keydown new keys
    if not old[k] then
      if not api.event("keydown", k) then return false end
    end
  end
  return true
end

function core.touch_inp(e, tid, fid, x, y)
  core.vpad_enabled = core.vpad_enabled or (e == 'fingerdown')
  if not core.vpad_enabled or not vpad.x or
    e ~= 'fingerup' and e ~= 'fingerdown'and
    e ~= 'fingermotion'  then
    return true
  end
  local w, h = gfx.win():size()
  x, y = w * x, h * y
  local fng = vpad.fingers[fid] or {}
  local new = {}
  if e == 'fingerdown' or e == 'fingermotion' then
    for _, b in ipairs { "z", "x", "escape" } do
      if ((x - vpad[b].x)^2 + (y - vpad[b].y)^2)^0.5 <= vpad[b].r then
        new[b] = true
        vpad.fingers[fid] = new
        return finger_process(fng, new)
      end
    end
    local dr = ((x - vpad.stick.x)^2 + (y - vpad.stick.y)^2)^0.5
    if dr <= vpad.stick.r and dr > (vpad.stick.r/4) + 1 then
      local dx = x - vpad.stick.x
      local dy = y - vpad.stick.y
      local a
      if math.abs(dy) > math.abs(dx) then
        a = math.abs(dx/dy)
      else
        a = math.abs(dy/dx)
      end
      local dia = a > 0.4 and a < 1
      if dia or math.abs(dy) > math.abs(dx) then
        new[dy > 0 and 'down' or 'up'] = true
      end
      if dia or math.abs(dx) > math.abs(dy) then
        new[dx > 0 and 'right' or 'left'] = true
      end
      vpad.fingers[fid] = new
      return finger_process(fng, new)
--    else
--      sys.window_mode 'fullscreen'
    end
  elseif e == 'fingerup' then
    finger_process(fng, {})
    vpad.fingers[fid] = nil
  end
  return true
end

function core.render(force)
  if not env.screen then
    return
  end
  local start = sys.time()
  if not force and start - last_render < fps then
    return
  end
  local win = gfx.win()
  if not win then return end -- minimized?
  local ww, hh = win:size()
  local w, h = env.screen:size()
  local xs, ys = ww/w, hh/h
  local scale = (xs <= ys) and xs or ys
  if scale > 1.0 and not core.scale then
    scale = math.floor(scale)
  end
  local dw = w * scale
  local dh = h * scale

  dw = math.floor(dw)
  dh = math.floor(dh)

  core.view_w, core.view_h = dw, dh
  core.view_x, core.view_y = math.floor((ww - dw)/2), math.floor((hh - dh)/2)

  if not gfx.expose then
    local win = gfx.win()
    win:clip(core.view_x, core.view_y,
      core.view_w, core.view_h)
    env.screen:stretch(win,
      core.view_x, core.view_y,
      core.view_w, core.view_h)
    gfx.update() -- no flip needed
  elseif core.vpad_enabled then
    core.view_y = 0
    gfx.expose(env.screen, core.view_x, core.view_y, core.view_w, core.view_h)
    local vx, vy = 0, core.view_h + core.view_y
    local vw, vh = ww, hh - vy
    core.vpad(vx, vy, vw, vh)
    gfx.update(vx, vy, vw, vh)
    gfx.flip()
  else
    gfx.expose(env.screen, core.view_x, core.view_y, core.view_w, core.view_h)
    gfx.flip()
  end
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
  while true do
    local r, v, a, b, c = sys.poll()
    if not r then
      break
    end
    if not core.touch_inp(r, v, a, b, c) or
      not api.event(r, v, a, b, c) then
      break
    end
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
        elseif e == 'stop' then
          table.remove(core.fn, i)
          collectgarbage("collect")
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
  return api.event() -- check is running
end

return core
