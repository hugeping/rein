gfx.win(385, 380)
local conf = {
  bg = 16,
  fg = 0,
}

local W, H = screen:size()
local win = {}
local sfont = font
local flr, ceil = math.floor, math.ceil
local fmt = string.format
local add = table.insert
local cat = function(a) return table.concat(a,'') end
win.__index = win

function win.new()
  local s = {}
  local w, h = sfont:size(" ")
  s.lines = flr(H/h)-1
  s.cols = flr(W/w)
  s.line = 1
  s.text = {{}}
  s.spw, s.sph = w, h
  setmetatable(s, win)
  return s
end

function win:write(f, ...)
  local s = self
  local t = utf.chars(fmt(f, ...):gsub("\r",""))
  local l = s.text[#s.text]
  for _,c in ipairs(t) do
    if c == '\n' or #l >= s.cols then
      l = {}
      add(s.text, l)
    end
    if c ~= '\n' then
      add(l, c)
    end
  end
  s:scroll()
end

function win:show()
  local s = self
  screen:clear(0, 0,
    s.cols*s.spw, s.lines*s.sph, conf.bg)
  local nr = 0
  for k = s.line, #s.text do
    gfx.print(cat(s.text[k]),
      0, nr*s.sph, conf.fg)
    nr = nr + 1
  end
  screen:clear(0, H-s.sph,
    W, s.sph, conf.bg)
  local t = utf.chars(s.inp)
  local off = #t - (s.cols-2)
  if off < 1 then off = 1 end
  local x, y = 0, H-s.sph
  for i=off,#t do
    gfx.print(t[i], x, y, conf.fg)
    x = x + s.spw
  end
  if flr(sys.time()*4) % 2 == 1 then
    screen:fill_rect(x, y, x + s.spw, y + s.sph, conf.fg)
  end
end

function win:scroll(delta)
  local s = self
  if delta then
    s.line = s.line + delta
    if s.line > #s.text - s.lines then
      s.line = #s.text - s.lines
    end
    if s.line < 1 then s.line = 1 end
    if #s.text - s.line >= s.lines then
      return
    end
  end
  if #s.text - s.line <= s.lines + 16 then
    s.line = #s.text - s.lines
    if s.line < 1 then s.line = 1 end
  end
end

local buf = win.new()
local NICK = ARGS[4] or string.format("rein%d", math.random(1000))
local HOST = ARGS[2] or 'irc.oftc.net'
local PORT = ARGS[3] or 6667

local thr = thread.start(function()
  local sock = require "sock"
  local nick, host, port = thread:read()
  local s,e = sock.dial(host, port)
  print("thread: connect", s, e)
  if not s then
    thread:write(false, e)
    return
  else
    thread:write(true)
  end
  s:write(string.format("NICK %s\r\nUSER %s localhost %s :%s\r\n",
    nick, nick, host, nick))
  while true do
     local r, v = thread:read(1/10)
     if r == 'quit' then
       break
     elseif r == 'send' then
       s:write(v..'\r\n')
     end
     if not s:poll() then
       thread:write(false, "Error reading from socket!")
       break
     end
     for l in s:lines() do
       thread:write(true, l)
     end
  end
  print("thread finished")
end)

buf:write("Connecting to %s:%d...",
  HOST, PORT)
buf:show() gfx.flip()

thr:write(NICK, HOST, PORT)

local r = thr:read()

if r then
  buf:write("connected\n")
else
  buf:write("error\n")
end

buf:show() gfx.flip()

function win:input(t)
  self.inp = (self.inp or '') .. t
end

function win:newline()
  local inp = self.inp or ''
  inp = inp:strip()
  if inp:startswith(":s") then
    self.channel = inp:sub(4):strip()
    self:write("Default channel: %s\n", self.channel)
    self.channel = self.channel ~= '' and self.channel or false
  elseif inp:startswith(":j ") then
    local c = inp:sub(4):strip()
    local m = "JOIN "..c
    thr:write('send', m)
    self:write("%s\n", m)
  elseif inp:startswith(":l ") then
    local c = inp:sub(4):strip()
    local m = "PART "..c.." :bye!"
    thr:write('send', m)
    self:write("%s\n", m)
  elseif self.channel then
    local m = "PRIVMSG "..self.channel.." :"..inp
    thr:write('send', m)
    self:write("%s:%s\n", NICK, inp)
  else
    thr:write('send', inp)
    self:write("%s\n", inp)
  end
  self.inp = ''
end

function win:backspace()
  local input = self.inp or ''
  local s = #input - utf.prev(input, #input)
  self.inp = input:sub(1, s)
end

function irc_rep(v)
  print(v)
  local user, cmd, par, s, txt
  if v:empty() then return end
  if v:sub(1, 1) == ':' then
    s = v:find(" ")
    user = v:sub(2, s - 1):gsub("^([^!]+)!.*$", "%1")
    v = v:sub(s + 1)
  end
  s = v:find(" ")
  cmd = v:sub(1, s - 1):strip()
  par = v:sub(s+1)
  s = par:find(":") or #par + 1
  txt = s and par:sub(s+1):strip()
  par = par:sub(1, s-1):strip()
  if cmd == 'PING' then
    thr:write('send', 'PONG '..txt)
    return
  elseif cmd == 'PONG' then
    return
  elseif cmd == 'PRIVMSG' then
    if buf.channel == par then
      return string.format("%s:%s", user, txt)
    else
      return string.format("%s@%s:%s", par, user, txt)
    end
  end
  return string.format("%s", txt) --%s(%s):%s", cmd, par, txt)
end

while r do
  local e, v = sys.input()
  if e == 'quit' then
    thr:write("quit")
    break
  elseif e == 'text' then
    buf:input(v)
  elseif e == 'keydown' and
    v == 'backspace' then
    buf:backspace()
  elseif e == 'keydown' and
    v == 'return' then
    buf:newline()
  elseif e == 'keydown' and
    v == 'v' and input.keydown 'ctrl' then
    buf:input(sys.clipboard())
  elseif e == 'keydown' and
    (v == 'pageup' or v == 'keypad 9') then
    buf:scroll(-buf.lines)
  elseif e == 'keydown' and
    (v == 'pagedown' or v == 'keypad 3') then
    buf:scroll(buf.lines)
  end
  if thr:poll() then
    e, v = thr:read()
    v = irc_rep(v)
    if v then
      buf:write("%s\n", v)
    end
    if not e then
      break
    end
  end
  buf:show()
  gfx.flip(1/20, true)
end
