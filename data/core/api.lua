local font = require "font"
local spr = require "spr"
local mixer = require "mixer"
local bit = require "bit"
local dump = require "dump"
local utf = require "utf"
local THREADED = not not thread
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
    [1] = { 0x1D, 0x2B, 0x53, 0xFF },
    [2] = { 0x7E, 0x25, 0x53, 0xFF },
    [3] = { 0x00, 0x87, 0x51, 0xFF },
    [4] = { 0xAB, 0x52, 0x36, 0xFF },
    [5] = { 0x5F, 0x57, 0x4F, 0xFF },
    [6] = { 0xC2, 0xC3, 0xC7, 0xFF },
    [7] = { 0xFF, 0xF1, 0xE8, 0xFF },
    [8] = { 0xFF, 0x00, 0x4D, 0xFF },
    [9] = { 0xFF, 0xA3, 0x00, 0xFF },
    [10] = { 0xFF, 0xEC, 0x27, 0xFF },
    [11] = { 0x00, 0xE4, 0x36, 0xFF },
    [12] = { 0x29, 0xAD, 0xFF, 0xFF },
    [13] = { 0x83, 0x76, 0x9C, 0xFF },
    [14] = { 0xFF, 0x77, 0xA8, 0xFF },
    [15] = { 0xFF, 0xCC, 0xAA, 0xFF },
    [16] = { 0xFF, 0xFF, 0xE8, 0xFF },
    [17] = { 0xEA, 0xFF, 0xFF, 0xff },
  };
  fg = { 0, 0, 0 };
  bg = 16;
  brd = { 0xde, 0xde, 0xde };
  font_large = "7x10.fnt",
  font = "7x8.fnt",
  font_tiny = 'pico8.fnt',
}

local env = {
  package = package,
  debug = debug,
  loadfile = loadfile,
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

env.__mods_loaded__ = {}

local function make_dofile(n, env)
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

local function make_require(n, env)
  if setfenv and false then
    setfenv(0, env)
  else
    local mods = env.__mods_loaded__
    if mods[n] then
      return mods[n]
    end
    local name = DATADIR..'/lib/'..n..'.lua'
    local f = io.open(name, "r")
    if f then
      f:close()
      mods[n] = make_dofile(name, env)
    else
      mods[n] = make_dofile(n..'.lua', env)
    end
    return mods[n]
  end
  return require(n)
end

function env.require(n)
  return make_require(n, env)
end

function env.dofile(n)
  return make_dofile(n, env)
end

local thread = thread or {}
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
    running = sys.running,
    time = sys.time,
    title = sys.title,
    log = sys.log,
    readdir = sys.readdir,
    chdir = sys.chdir,
    mkdir = sys.mkdir,
    hidemouse = sys.hidemouse,
    clipboard = sys.clipboard,
    newrand = sys.newrand,
  },
  thread = thread,
  net = net,
  mixer = mixer,
  synth = synth,
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

function env_ro.gfx.win(w, h, fnt) -- create new win or change
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
    if fnt then
      fnt = font.new(fnt)
    end
    if not fnt then
      if w < 192 then
        env_ro.font = font.new(DATADIR..'/fonts/'..conf.font_tiny)
      elseif h >= 380 then
        env_ro.font = font.new(DATADIR..'/fonts/'..conf.font_large)
      else
        env_ro.font = font.new(DATADIR..'/fonts/'..conf.font)
      end
    else
      env_ro.font = fnt
    end
    env_ro.screen = nscr
    conf.w, conf.h = nscr:size()
    env.gfx.border()
    nscr:clear(conf.bg)
  end
  return oscr
end

local flipsx, flipsy, flipsxy = {}, {}

function env_ro.gfx.spr(data, nr, x, y, w, h, flipx, flipy)
  local flips
  local W, H = data:size()
  local nsp = math.floor(W/8)
  w = w or 1
  h = h or 1
  local fx = nr % nsp
  local fy = math.floor(nr / nsp)
  local flips
  if flipx and not flipy then
    flips = flipsx
  elseif not flipx and flipy then
    flips = flipsy
  elseif flipx and flipy then
    flips = flipsxy
  end

  if not flips then
    data:blend(fx * 8, fy * 8, w * 8, h * 8, env.screen, x, y)
    return
  end
  flips[data] = flips[data] or {}
  flips = flips[data]

  if flips[nr] then
    flips[nr]:blend(env.screen, x, y)
    return
  end
  flips[nr] = gfx.new(w*8, h*8)
  data:blend(fx * 8, fy * 8, w * 8, h * 8, flips[nr], 0, 0)
  if flipx then
    flips[nr] = flips[nr]:flip(true, false)
  end
  if flipy then
    flips[nr] = flips[nr]:flip(false, true)
  end
  flips[nr]:blend(env.screen, x, y)
  return
end

function env_ro.gfx.loadmap(fname)
  fname = fname:strip():gsub("\r", "")
  local f, e
  if fname:find("\n") then
    f = { lines = function() return fname:lines() end, close = function() end }
  else
    f, e = io.open(fname, "rb")
  end
  if not f then return false, e end
  local map = {}
  local y = 0
  for l in f:lines() do
    y = y + 1
    map[y] = {}
    for x = 1, l:len(), 2 do
      map[y][(x-1)/2+1] = tonumber(l:sub(x, x+1), 16)
    end
  end
  f:close()
  return map
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
  conf.brd = { gfx.pal(col or conf.brd) }
  if not gfx.expose then
    gfx.win():clear(conf.brd)
  else
    gfx.background(conf.brd)
  end
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

function env_ro.gfx.render()
  core.render(true)
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

function env_ro.sys.getopt(...)
  return core.getopt(...)
end

function env_ro.sys.input(reset)
  if reset == false then
    return #input.fifo ~= 0
  end
  if #input.fifo == 0 then
    return
  end
  local v = table.remove(input.fifo, 1)
  if reset then
    input.fifo = {}
  end
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

function env.sys.dirname(f)
  if not f:find("[/\\]") then
    local ff = f:gsub("^([A-Z]:).*$", "%1") -- win?
    if ff == f then return './' end
    return f
  end
  f = f:gsub("[/\\][^/\\]+$", "")
  return f
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
    if not THREADED and left > 1/100 then
      sys.wait(1/100)
    elseif not sys.wait(left) then
      break
    end
  until interrupt
end

function env_ro.error(text)
  env.screen:noclip()
  env.screen:nooffset()
  env.screen:clear(conf.bg)
  env.gfx.print(text or 'Error', 0, 0, conf.fg, true)
  env.gfx.render()
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
      y = y - off
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

function env_ro.sys.suspend(...)
  return coroutine.yield 'suspend'
end

function env_ro.sys.exec(fn, ...)
  local newenv = {
    ARGS = { fn, ... },
    __mods_loaded__ = {},
  }
  newenv.dofile = function(f) return make_dofile(f, newenv) end
  newenv.require = function(f) return make_require(f, newenv) end
  rawset(env, '__index', env)
  setmetatable(newenv, env)
  local r, e = core.go(fn, newenv)
  if not r then
    local msg = e
    r, e = env_ro.sys.go(function() error(msg) end)
  end
  if not r then return false, e end
  return true
end

function env_ro.sys.appdir(app)
  if type(app) ~= 'string' then
    return false, "Invalid argument"
  end
  local h = os.getenv('HOME') or os.getenv('home')
  local path = h and string.format("%s/.rein", h) or (DATADIR..'/save')
  if sys.mkdir(path) and sys.mkdir(path .."/"..app) then
    return path .. "/".. app
  end
  core.err("Can not create savedir: "..path("/")..app)
end

function env_ro.sys.stop(fn)
  if not fn then
    return coroutine.yield 'stop'
  end
  return core.stop(fn)
end

function env_ro.sys.yield(...)
  return coroutine.yield(...)
end

local api = { running = true }

function env_ro.sys.running()
  return api.running
end

function api.init(core_mod)
  math.randomseed(os.time())
  env_ro.font = font.new(DATADIR..'/fonts/'..conf.font)
  core = core_mod
  if not env_ro.font then
    return false, string.format("Can't load font %q", DATADIR..'/fonts/'..conf.font)
  end
  mixer.init(core_mod)
  for i=0,17 do
    gfx.pal(i, conf.pal[i])
  end
  env.screen:clear(conf.bg)
  return env
end

local event_filter = {
  quit = true,
--  resized = true,
  text = true,
  keydown = true,
  keyup = true,
  mousedown = true,
  mouseup = true,
  mousewheel = true,
  mousemotion = true,
}

function api.event(e, v, a, b, c)
  if not api.running then
    return false
  end
  if not e then
    return true
  end
  if e == 'quit' then
    api.running = false
    input.fifo  = {}
    mixer.done()
  elseif e == 'keydown' and (v == 'escape' and input.kbd.shift)
    and #core.suspended > 0 then
    mixer.done()
    core.stop()
    return true
  elseif e == 'mousemotion' then
    v, a = core.abs2rel(v, a)
  elseif e == 'mousedown' or e == 'mouseup' then
    a, b = core.abs2rel(a, b)
  end

  if e == 'keydown' and v == 'return' and input.kbd.alt then
    conf.fullscreen = not conf.fullscreen
    if conf.fullscreen then
      sys.window_mode 'fullscreen'
    else
      sys.window_mode 'normal'
    end
    e = nil
  end

  if event_filter[e] and #input.fifo < 32 then
    local ev = { nam = e, args = { v, a, b, c } }
    table.insert(input.fifo, ev)
  end

  if e == 'resized' or e == 'exposed' then
    if not gfx.expose then
      gfx.win():clear(conf.brd)
    else
      gfx.background(conf.brd)
    end
    return true
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
