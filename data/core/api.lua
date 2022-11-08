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
    [16] = { 0xFF, 0xFF, 0xE8, 0xff },
  };
  fg = { 0, 0, 0 };
  bg = 16;
  brd = { 0xde, 0xde, 0xde };
  font = "fonts/8x8.fnt",
}

local env = {
  type = type,
  rawset = rawset,
  rawget = rawget,
  setmetatable = setmetatable,
  getmetatable = getmetatable,
  table = table,
  math = math,
  bit = bit,
  string = string,
  pairs = pairs,
  ipairs = ipairs,
  io = io,
  os = os,
  tonumber = tonumber,
  tostring = tostring,
  coroutine = coroutine,
  print = print,
  DATADIR = DATADIR,
  SCALE = SCALE,
  VERSION = VERSION,
  collectgarbage = collectgarbage,
}

env._G = env

local mods = {}
function env.require(n)
  if setfenv then
    setfenv(0, env)
  else
    if mods[n] then
      return mods[n]
    end
    local name = DATADIR..'/lib/'..n..'.lua'
    local f = io.open(name, "r")
    if f then
      f:close()
      mods[n] = env.dofile(name)
    else
      mods[n] = env.dofile(n..'.lua')
    end
    return mods[n]
  end
  return require(n)
end

function env.dofile(n)
  if setfenv then
    setfenv(0, env)
  else
    local r, e = loadfile(n, "t", env)
    if not r then
      core.err(e..'\n'..debug.traceback())
    end
    return r()
  end
  return dofile(n)
end

function thread.start(code)
  local r, e, c
  if type(code) ~= 'function' and type(code) ~= 'string' then
    error("Wrong argument", 2)
  end
  if type(code) == 'string' then
    r, e, c = thread.new(code, true)
  else
    -- try to serialize it!
    r, e = dump.new(code)
    if not r and e then -- error?
      core.err("Can not start thread.\n"..e)
    end
    code = string.format(
      "local f, e = require('dump').new [=========[\n%s"..
      "]=========]\n"..
      "if not f and e then\n"..
      " error(e)\n"..
      "end\n"..
      "f()\n", r)
    r, e, c = thread.new(code)
  end
  if not r then
    local msg = string.format("%s\n%s", e, c)
    core.err(msg)
  end
  return r
end

local env_ro = {
  screen = gfx.new(conf.w, conf.h),
  utf = utf,
  gfx = {
    pal = gfx.pal,
    icon = gfx.icon,
  };
  sys = {
    time = sys.time,
    title = sys.title,
    log = sys.log,
    readdir = sys.readdir,
    chdir = sys.chdir,
    mkdir = sys.mkdir,
    initrnd = sys.initrnd,
    hidemouse = sys.hidemouse,
    audio = sys.audio,
  };
  thread = thread,
  mixer = mixer,
  input = {},
}

env_ro.__index = env_ro
env_ro.__newindex = function(t, nam, val)
  if rawget(env_ro, nam) then
    error("Can not change readonly value: "..nam, 2)
  end
  rawset(t, nam, val)
end

setmetatable(env, env_ro)

function env_ro.gfx.win(w, h) -- create new win or change
  local oscr = env_ro.screen
  if type(w) == 'userdata' then -- new screen?
    env_ro.screen = w
    return oscr
  end
  local nscr
  if w then
    nscr = gfx.new(w, h)
  end
  if nscr then
    if w < 192 then
      env_ro.font = font.new(DATADIR..'/fonts/pico8.fnt')
    else
      env_ro.font = font.new(DATADIR..'/fonts/8x8.fnt')
    end
    env_ro.screen = nscr
    conf.w, conf.h = nscr:size()
    nscr:clear(conf.bg)
  end
  return oscr
end

function env_ro.gfx.new(x, y)
  if type(x) == 'number' and type(y) == 'number' then
    return gfx.new(x, y)
  end
  if type(x) == 'string' then
    if x:find("\n") then
      return spr.new({ lines = function() return x:lines() end }, y)
    end
    if x:find("%.[sS][pP][rR]$") then
      return spr.new(x, y)
    end
  end
  return gfx.new(x, y)
end

function env_ro.gfx.printf(x, y, col, fmt, ...)
  return env.gfx.print(string.format(fmt, ...), x, y, col)
end


local last_flip = 0
local flips = {}

function env_ro.gfx.fg(col)
  conf.fg = { gfx.pal(col or conf.fg) }
end

function env_ro.gfx.bg(col)
  conf.bg = { gfx.pal(col or conf.bg) }
end

function env_ro.gfx.border(col)
  conf.brd = { gfx.pal(col or conf.bg) }
  gfx.win():clear(conf.brd)
end

function env_ro.gfx.font(fname, ...)
  if type(fname) == 'string' and fname:find("%.[fF][nN][tT]$") then
    return font.new(fname, ...)
  end
  return gfx.font(fname, ...)
end

local framedrop

function env_ro.gfx.framedrop()
  return framedrop
end

function env_ro.gfx.flip(fps, interrupt)
  if not framedrop then -- drop every 2nd frame if needed
    core.render(true)
  end
  local cur_time = sys.time()
  local delta = (fps or conf.fps) - (cur_time - last_flip)
  framedrop = delta < 0 and not framedrop
  env_ro.sys.sleep(delta, interrupt)
  last_flip = sys.time()
  table.insert(flips, last_flip)
  if #flips > 50 then
    table.remove(flips, 1)
  end
  if #flips == 1 then
    return 0
  end
  return math.floor(#flips / math.abs(last_flip - flips[1]))
end

function env_ro.input.mouse()
  return input.mouse.x or 0, input.mouse.y or 0, input.mouse.btn
end

function env_ro.sys.input()
  if #input.fifo == 0 then
    return
  end
  local v = table.remove(input.fifo, 1)
  return v.nam, table.unpack(v.args)
end

function env_ro.input.keydown(name)
  return input.kbd[name]
end

function env_ro.input.keypress(name) -- single press
  local r = input.kbd[name]
  if not r or r == 1 then
    return false
  end
  input.kbd[name] = 1
  return true
end

function env.sys.sleep(to, interrupt)
  local start = sys.time()
  repeat
    coroutine.yield()
    if interrupt and #input.fifo > 0 then
      break
    end
    local pass = sys.time() - start
    local left = to - pass
    if left <= 0 then
      break
    end
    sys.wait(left)
  until interrupt
end

function env_ro.error(text)
  env.screen:clear(conf.bg)
  env.gfx.print(text, 0, 0, conf.fg, true)
  core.err_msg = text
  if not core.running() then
    return
  end
  coroutine.yield()
end

function env_ro.gfx.print(text, x, y, col, scroll)
  text = tostring(text)
  if not env.screen then
    sys.log(text)
    return
  end
  x = x or 0
  y = y or 0
  local startx = x
  col = col or conf.fg

  text = text:gsub("\r", ""):gsub("\t", "    ")

  local w, h = env.screen:size()
  local ww, hh = env.font:size("")

  while text ~= '' do
    local s, _ = text:find("[/:,. \n]", 1)
    if not s then s = text:len() end
    local nl = text:sub(s, s) == '\n'
    local word = text:sub(1, s):gsub("\n$", "")
    local p = env.font:text(word, col)
    if p then
      ww, hh = p:size()
    else
      ww = 0
    end
    if x + ww >= w and scroll then
      x = startx
      y = y + hh
    end

    if scroll and y > h - hh then -- vertical overflow
      local off = math.floor(y - (h - hh))
      env.screen:copy(0, off, w, h - off, env.screen, 0, 0) -- scroll
      env.screen:clear(0, h - off, w, off, conf.bg)
      y = h - hh
    end

    if p then
      p:blend(env.screen, x, y)
    end
    x = x + ww
    text = text:sub(s + 1)
    if nl then
      x = startx
      y = y + hh
    end
  end
end

function env_ro.sprite_data(fname)
  if fname:find("\n") then
    return spr.new({ lines = function() return fname:lines() end }, true)
  end
  return spr.new(fname)
end

function env_ro.sys.go(fn)
  return core.go(fn, env)
end

function env_ro.sys.exec(fn, ...)
  local newenv = {
    ARGS = { fn, ... }
  }
  rawset(env, '__index', env)
  setmetatable(newenv, env)
  return core.go(fn, newenv)
end

function env_ro.sys.stop(fn)
  return core.stop(fn)
end

function env_ro.sys.yield(...)
  return coroutine.yield(...)
end

local api = { running = true }

function api.init(core_mod)
  math.randomseed(os.time())
  env_ro.font = font.new(DATADIR..'/'..conf.font)
  core = core_mod
  if not env_ro.font then
    return false, string.format("Can't load font %q", DATADIR..'/'..conf.font)
  end
  mixer.init(core_mod)
  for i=0,16 do
    gfx.pal(i, conf.pal[i])
  end
  env.screen:clear(conf.bg)
  return env
end

function api.event(e, v, a, b, c)
  if not api.running then
    return false
  end
  if not e then
    return true
  end
  if e == 'resized' or e == 'exposed' then
    gfx.win():clear(conf.brd)
    return true
  end
  if e == 'quit' then
    api.running = false
    input.fifo  = {}
    mixer.stop()
  end

  if e == 'mousemotion' then
    v, a = core.abs2rel(v, a)
  elseif e == 'mousedown' or e == 'mouseup' then
    a, b = core.abs2rel(a, b)
  end

  if (e == 'quit' or e == 'text' or e == 'keydown' or e == 'keyup' or
    e == 'mousedown' or e == 'mouseup' or e == 'mousewheel' or e == 'mousemotion')
      and #input.fifo < 32 then
    local ev = { nam = e, args = { v, a, b, c } }
    table.insert(input.fifo, ev)
  end

  if e == 'keyup' then
    if v:find("alt$") then
      input.kbd.alt = false
    elseif v:find("ctrl$") then
      input.kbd.ctrl = false
    elseif v:find("shift$") then
      input.kbd.shift = false
    end
    input.kbd[v] = false
  elseif e == 'keydown' then
    if v:find("alt$") then
      input.kbd.alt = true
    elseif v:find("ctrl$") then
      input.kbd.ctrl = true
    elseif v:find("shift$") then
      input.kbd.shift = true
    end
    input.kbd[v] = true
    if v == 'return' and input.kbd.alt then
      conf.fullscreen = not conf.fullscreen
      if conf.fullscreen then
        sys.window_mode 'fullscreen'
      else
        sys.window_mode 'normal'
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
