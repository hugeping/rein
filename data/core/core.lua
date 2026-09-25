local api = require "api"
local mixer = require "mixer"
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
  local _, v = coroutine.running()
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
  io.stderr:write(t, '\n')
  io.stderr:flush()
  if core.show_error then
    core.show_error(t)
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

  for _, v in ipairs(sys.readdir(DATADIR..'/apps/') or {}) do
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

local vpad = { fingers = {}, btn = {} }
local vpad_col = { 192, 192, 192, 255 }
-- translucent colors for the vpad-over-screen mode
local vpad_col_ov = { 224, 224, 224, 100 }

function core.vpad(x, y, w, h, overlay)
  if vpad.x == x and vpad.y == y and
    vpad.w == w and vpad.h == h and
    vpad.overlay == overlay and vpad.pxl then
    return vpad.pxl
  end

  local win = gfx.new(w, h)
  if not win then return end -- 0?
  local col = overlay and vpad_col_ov or vpad_col
  win:clear(0, 0, w, h, { 0, 0, 0, overlay and 0 or 255 })
  vpad.x, vpad.y, vpad.w, vpad.h = x, y, w, h
  vpad.overlay = overlay
  -- stick: bottom left corner, its top edge is level with the top button
  local rs = math.min(h * 0.45, w * 0.25)
  local ytop = h - 2 * rs
  -- z and x on the right, a "/" diagonal (45 degrees);
  -- button diameter <= stick radius
  local mxf = 0.25  -- side margin, in button radii
  local df = 1.6    -- diagonal offset, in button radii
  local kf = 2 + mxf + df
  local rb = math.min(rs * 0.5, (w - 2 * rs) / kf, w / (2 * kf))
  local gap = rb * mxf
  local mx = rb * mxf
  local xc = rs
  local yc = h - rs
  vpad.stick = { x = xc + x, y = yc + y, r = rs }
  win:circle(xc, yc, rs, col)
  local d = rs/4
  win:circle(xc, yc, rs / 2, col)
  local r = rs * 0.9
  win:fill_poly( {xc, yc - r, xc + d, yc - r + d, xc - d, yc - r + d }, col)
  win:fill_poly( {xc, yc + r, xc + d, yc + r - d, xc - d, yc + r - d }, col)
  win:fill_poly( {xc - r, yc, xc - r + d, yc - d, xc - r + d, yc + d }, col)
  win:fill_poly( {xc + r, yc, xc + r - d, yc - d, xc + r - d, yc + d }, col)
  xc = w - rb - mx
  yc = ytop + rb
  vpad.btn.z = { x = xc + x, y = yc + y, r = rb }
  win:circle(xc, yc, rb, col)
  win:circle(xc, yc, rb/2, col)
  -- x: left of z and lower, keeping the 45 degree diagonal
  xc = xc - rb * df
  yc = yc + rb * df
  vpad.btn.x = { x = xc + x, y = yc + y, r = rb }
  win:circle(xc, yc, rb, col)
  win:rect(xc - rb/2, yc - rb/2, xc + rb/2, yc + rb/2, col)
  local re = rb * 0.5
  xc = w - 1.5*re
  yc = h - 1.5*re
  vpad.btn.escape = { x = xc + x, y = yc + y, r = re }
  win:circle(xc, yc, re, col)
  win:rect(xc - re/1.5, yc - re/4, xc + re/1.5, yc + re/4, col)
  vpad.pxl = win
  return win
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

function core.touch_inp(e, _, fid, x, y)
  core.vpad_enabled = core.vpad_enabled or (e == 'fingerdown')
  if not core.vpad_enabled or not vpad.x or
    e ~= 'fingerup' and e ~= 'fingerdown'and
    e ~= 'fingermotion'  then
    return true
  end
  local w, h = sys.window_size()
  x, y = w * x, h * y
  local fng = vpad.fingers[fid] or {}
  local new = {}
  if e == 'fingerdown' or e == 'fingermotion' then
    for _, b in ipairs { "z", "x", "escape" } do
      if ((x - vpad.btn[b].x)^2 + (y - vpad.btn[b].y)^2)^0.5 <= vpad.btn[b].r then
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
  local ww, hh = sys.window_size()
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

  gfx.clear()
  if core.vpad_enabled then
    if hh - dh < hh / 3 then
      -- not enough room below the screen: draw the vpad over it
      env.screen:expose(core.view_x, core.view_y, core.view_w, core.view_h)
      local vh = math.floor(dh * 0.4)
      if vh > 0 then
        local vy = core.view_y + dh - vh
        local vp = core.vpad(core.view_x, vy, dw, vh, true)
        if vp then vp:expose(core.view_x, vy, dw, vh) end
      end
    else
      core.view_y = 0
      local vx, vy = 0, core.view_h
      local vw, vh = ww, hh - vy
      local vp = core.vpad(vx, vy, vw, vh)
      if vp then vp:expose(vx, vy) end
      env.screen:expose(core.view_x, core.view_y, core.view_w, core.view_h)
    end
  else
    env.screen:expose(core.view_x, core.view_y, core.view_w, core.view_h)
  end
  api.record(env.screen)
  last_render = start
  return true
end

function core.abs2rel(x, y)
  if not env.screen then
    return x, y
  end
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
          core.err(e .. '\n' .. debug.traceback(fn))
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
    gfx.flip()
    sys.sleep(fps)
  end

  if core.fn.kill then -- pending stop
    mixer.done()
    core.stop()
  end

  return api.event() -- check is running
end

return core
