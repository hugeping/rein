gfx.win(385, 380)
local HISTORY_SIZE = 16384

local conf = {
  bg = 16,
  fg = 0,
  sel = 12,
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
      l = { brk = c ~= '\n' }
      add(s.text, l)
    end
    if c ~= '\n' then
      add(l, c)
    end
  end
  while #s.text > HISTORY_SIZE do
    table.remove(s.text, 1)
    s.line = s.line + 1
  end
  s:scroll()
end

function win:getsel()
  local s = self
  local x1, y1 = s.sel_x1 or 0, s.sel_y1 or 0
  local x2, y2 = s.sel_x2 or 0, s.sel_y2 or 0
  if y1 > y2 or (y1 == y2 and x1 > x2) then
    x1, x2 = x2, x1
    y1, y2 = y2, y1
  end
  return x1, y1, x2, y2
end

function win:copy()
  local s = self
  local x1, y1, x2, y2 = s:getsel()
  if x1 == 0 then
    return
  end
  local txt = ''
  for k = y1, y2 do
    for x = 1, s.text[k] and #s.text[k] or 0 do
      if k == y1 and x >= x1 or k == y2 and x <= x2 or
        k > y1 and k < y2 then
        if y1 ~= y2 or (x >= x1 and x <= x2) then
          txt = txt .. s.text[k][x]
        end
      end
    end
    if not s.text[k+1] or not s.text[k+1].brk then
      txt = txt .. '\n'
    end
  end
  txt = txt:strip()
  sys.clipboard(txt)
end

function win:show()
  local s = self
  screen:clear(0, 0,
    s.cols*s.spw, s.lines*s.sph, conf.bg)
  local nr = 0
  local x1, y1, x2, y2 = s:getsel()
  for k = s.line, #s.text do
    for x = 1, #s.text[k] do
      if k == y1 and x >= x1 or k == y2 and x <= x2 or
        k > y1 and k < y2 then
        if y1 ~= y2 or (x >= x1 and x <= x2) then
          screen:clear((x-1)*s.spw, nr*s.sph, s.spw, s.sph, conf.sel)
        end
      end
      gfx.print(s.text[k][x], (x-1)*s.spw, nr*s.sph, conf.fg)
    end
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
  local delay = 1/20
  local lines = {}
  local err
  while true do
     local r, v = thread:read(delay)
     if r == 'quit' then
       break
     elseif r == 'send' then
       s:write(v..'\r\n')
     elseif r == 'read' then
       for _, l in ipairs(lines) do
         thread:write(true, l)
       end
       lines = {}
       thread:write(false, err)
     end
     if not err and not s:poll() then
       err = "Error reading from socket!"
     end
     delay = 1/20
     for l in s:lines() do
       table.insert(lines, l)
       delay = 1/100
     end
  end
  print("thread finished")
end)

buf:write("Connecting to %s:%d...",
  HOST, PORT)
buf:show() gfx.render()
thr:write(NICK, HOST, PORT)

local r = thr:read()

if r then
  buf:write("connected\n")
else
  buf:write("error\n")
end

buf:show() gfx.render()

function win:input(t)
  if t == false then self.inp = '' return end
  self.inp = (self.inp or '') .. t
end

function win:newline()
  local inp = self.inp or ''
  inp = inp:strip()
  local a = inp:split()
  local cmd = a[1]
  table.remove(a, 1)
  if cmd == ':s' then
    self.channel = a[1] or ''
    self:write("Default channel: %s\n", self.channel)
    self.channel = self.channel ~= '' and self.channel or false
  elseif cmd == ':m' and a[1] then
    local s = inp:find(a[1], 4, true)
    local txt = inp:sub(s+a[1]:len()+1):strip()
    local m = "PRIVMSG "..a[1].." :"..txt
    thr:write('send', m)
    self:write("%s\n", m)
  elseif cmd == ':j' and a[1] then
    local c = a[1]
    local m = "JOIN "..c
    thr:write('send', m)
    self:write("%s\n", m)
  elseif cmd == ':l' then
    local c = a[1] or self.channel
    if c then
      if c == self.channel then self.channel = nil end
      local m = "PART "..c.." :bye!"
      thr:write('send', m)
      self:write("%s\n", m)
    end
  elseif cmd:startswith("/") then
    inp = inp:gsub("^[ \t]*/", "")
    thr:write('send', inp)
    self:write("%s\n", inp)
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

function win:mouse2pos(x, y)
  local s = self
  local sx, sy = flr(x / s.spw) + 1,
    s.line + flr(y / s.sph)
  return sx, sy
end

function win:motion()
  local s = self
  if not s.select  then
    return
  end
  local x, y = input.mouse()
  x, y = s:mouse2pos(x, y)
  s.sel_x2, s.sel_y2 = x, y
end

function win:click(press, mb, x, y)
  local s = self
  x, y = s:mouse2pos(x, y)
  if not s.text[y] then
    return
  end
  s.select = press
  if not s.text[y][x] then
    x = #s.text[y]
  end
  if press then
    s.sel_x1, s.sel_y1 = x, y
    s.sel_x2, s.sel_y2 = x, y
  end
end

local last_user
local last_pfx
function irc_rep(v)
  print(v)
  local user, cmd, par, s, txt
  if v:empty() then return end
  if v:sub(1, 1) == ':' then
    s = v:find(" ") or #v + 1
    user = v:sub(2, s - 1):gsub("^([^!]+)!.*$", "%1")
    v = v:sub(s + 1)
  end
  s = v:find(" ")
  if not s then s = #v + 1 end
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
      return string.format("%s:%s\n", user, txt)
    else
      return string.format("%s@%s:%s\n", par, user, txt)
    end
  end
  if cmd == "NICK" and user == NICK then
    NICK = txt
  end
  user = (user and user..':') or ''
  if user == last_user then user = '' else last_user = user end
  if par ~= '' then par = "("..par..")" end
  local pfx = string.format("%s%s", cmd, par == '' and ' ' or par)
  if pfx == last_pfx then pfx = '' else last_pfx = pfx end
  return string.format("%s%s%s", user, pfx, txt) --%s(%s):%s", cmd, par, txt)
end

local HELP = [[
Arguments:
rein irc.lua <server> <port> <nick>

Commands:
:j channel      - join channel
:m channel text - send message
:l channel      - leave channel
:s channel      - set default channel
:s              - no default channel
/COMMAND        - send COMMAND as is

Keys:
ctrl-k          - clear input line
ctrl-c          - copy selection
ctrl-v          - paste to input

Mouse:
motion+click    - selection

All other messages goes to server as-is.
While in :s channel mode, all messages goes
to that channel via PRIVMSG.
]]

while r do
  while help_mode do
    screen:clear(conf.bg)
    gfx.print(HELP, 0, 0, conf.fg, true)
    if sys.input() == 'keydown' then
      help_mode = false
      break
    end
    coroutine.yield()
  end
  local e, v, a, b = sys.input()
  if e == 'quit' then
    thr:write("quit")
    break
  elseif e == 'keydown' and
    v == 'f1' then
    help_mode = not help_mode
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
    buf:input(sys.clipboard() or '')
  elseif e == 'keydown' and
    v == 'c' and input.keydown 'ctrl' then
    buf:copy()
  elseif e == 'keydown' and
    v == 'k' and input.keydown 'ctrl' then
    buf:input(false)
  elseif e == 'keydown' and
    (v == 'pageup' or v == 'keypad 9') then
    buf:scroll(-buf.lines)
  elseif e == 'keydown' and
    (v == 'pagedown' or v == 'keypad 3') then
    buf:scroll(buf.lines)
  elseif e == 'mousedown' or e == 'mouseup' then
    buf:click(e == 'mousedown', v, a, b)
  elseif e == 'mousemotion' then
    buf:motion()
  end
  local delay = 1/20
  thr:write('read')
  local inp = e
  while true do
    e, v = thr:read()
    if not e then
      if v then -- fatal error
        buf:write("%s\n", v)
        thr:write("quit")
        r = false
      end
      break
    end
    delay = 0
    v = irc_rep(v)
    if v then
      buf:write("%s\n", v)
    end
  end
  if inp or delay == 0 then
    buf:show()
  end
  gfx.flip(delay, true)
end
