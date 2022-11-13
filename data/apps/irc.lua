local conf = {
  w = 385,
  h = 380,
  bg = 16,
  fg = 0,
  sel = 12,
  wordbreak = true,
  history_size = 16384,
  dict_size = 1024,
}

gfx.win(conf.w, conf.h)

gfx.border(conf.bg)
local W, H = screen:size()
local win = {}
local sfont = font
local flr, ceil = math.floor, math.ceil
local fmt = string.format
local add = table.insert
local del = table.remove
local cat = function(a) return table.concat(a,'') end
win.__index = win

function win.new()
  local s = { cur = 1, inp = {} }
  local w, h = sfont:size(" ")
  s.lines = flr(H/h)-1
  s.cols = flr(W/w)
  s.line = 1
  s.text = {{}}
  s.dict = {}
  s.spw, s.sph = w, h
  setmetatable(s, win)
  return s
end

function last_word(t)
  for i=#t,1,-1 do
    if t[i]:find("[ \t.,():;/%-!?]") then
      return i + 1
    end
  end
end

function win:fill_dict(t)
  local dict = self.dict
  dict.__hash__ = dict.__hash__ or {}
  for l in t:lines() do
    for _, w in ipairs(l:split(" \t.,:?!@#$*()<>/~-")) do
      if not dict.__hash__[w] then
        add(dict, w)
        dict.__hash__[w] = true
      end
      if #dict > conf.dict_size then
        dict.__hash__[del(dict, 1)] = nil
      end
    end
  end
end

function win:compl(t)
  local a = t:split()
  local w = a[#a] -- last word
  if not w then return t end
  local compl = {}
  for _, d in ipairs(self.dict) do
    if d:startswith(w) then
      add(compl, d)
    end
  end
  if #compl == 0 then return t end
  local max = utf.chars(compl[1])
  local u
  local nr = #max
  for _, v in ipairs(compl) do
    for i=1, nr do
      u = utf.chars(v)
      if max[i] ~= u[i] then
        nr = i - 1
        break
      end
    end
  end
  w = ''
  for i=1, nr do w = w .. max[i] end
  if not t:find(" ") then
    return w
  end
  t = t:gsub("[ \t][^ \t]+$", "")
  t = t .. ' '.. w
  return t
end

function win:write(f, ...)
  local s = self
  local txt = fmt(f, ...):gsub("\r","")
  self:fill_dict(txt)
  local t = utf.chars(txt)
  local l = s.text[#s.text]
  local nl
  for _,c in ipairs(t) do
    if c == '\n' or #l >= s.cols then
      nl = { brk = c ~= '\n' }
      if c ~= '\n' and conf.wordbreak then
        local w = last_word(l)
        if w and w > 1 then
          for i = w, #l do
            add(nl, del(l, w))
          end
        end
      end
      add(s.text, nl)
      l = nl
    end
    if c ~= '\n' then
      add(l, c)
    end
  end
  while #s.text > conf.history_size do
    del(s.text, 1)
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
  local t = s.inp
  local off = s.inpoff or 1
  if s.cur - off >= s.cols - 1 then off = s.cur - s.cols + 1 end
  if s.cur - off < 1 then off = s.cur end
  s.inpoff = off
  local x, y = 0, H-s.sph
  for i=off,#t do
    gfx.print(t[i], x, y, conf.fg)
    x = x + s.spw
  end
  x = (s.cur - off)*s.spw
--  if flr(sys.time()*4) % 2 == 1 then
  for yy=1,s.sph do
    for xx=1,s.spw do
      local r, g, b = screen:val(x + xx - 1, y + yy -1)
      r = bit.bxor(r, 0xff)
      g = bit.bxor(g, 0xff)
      b = bit.bxor(b, 0xff)
      screen:val(x + xx - 1, y + yy - 1, { r, g, b, 255 })
    end
  end
end

function win:tail()
  local s = self
  s.line = #s.text - s.lines
  if s.line < 1 then s.line = 1 end
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
local JOIN = ARGS[5]
local NICK = ARGS[4] or string.format("rein%d", math.random(1000))
local HOST = ARGS[2] or 'irc.oftc.net'
local PORT = ARGS[3] or 6667

if #ARGS == 1 then
  JOIN="#rein" -- ;)
end

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
     local r, v = thread:poll(delay)
     if r then
       r, v = thread:read()
     elseif v then -- read new msg
       r = 'read'
     end
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
  if t == false then self.inp = {} self.cur = 1 return end
  for _, v in ipairs(utf.chars(t)) do
    add(self.inp, self.cur, v)
    self.cur = self.cur + 1
  end
end

function win:cursor(dx)
  self.cur = self.cur + dx
  if self.cur < 1 then self.cur = 1 end
  if self.cur > #self.inp then self.cur = #self.inp + 1 end
end

function win:newline()
  local inp = cat(self.inp)
  inp = inp:strip()
  local a = inp:split()
  local cmd = a[1]
  del(a, 1)
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
  elseif cmd and cmd:startswith("/") then
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
  self:input(false)
  self:tail()
end

function win:backspace()
  if self.cur <= 1 then return end
  self.cur = self.cur - 1
  del(self.inp, self.cur)
end

function win:delete()
  if self.cur > #self.inp then
    return
  end
  del(self.inp, self.cur)
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
    return 'PONG '..txt, true
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
  return string.format("%s%s%s%s", user, pfx,
    (user..pfx):empty() and '' or ' ', txt) --%s(%s):%s", cmd, par, txt)
end

local HELP = [==[
Arguments:
rein irc.lua <server> [<port> [<nick> [<channel]]]

W/o args:
Connect to irc.oftc.net 6667 rein<random> #instead

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
ctrl-k          - clear input line
ctrl-a/home     - begin of input
ctrl-e/end      - end of input

Mouse:
motion+click    - selection

All other messages goes to server as-is.
While in :s channel mode, all messages goes
to that channel via PRIVMSG.
]==]

if JOIN then
  buf:input("/JOIN "..JOIN)
  buf:newline()
  buf:input(":s "..JOIN)
  buf:newline()
end
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
  elseif e == 'text' then
    buf:input(v)
  elseif e == 'keydown' then
    if v == 'f1' then
      help_mode = not help_mode
    elseif v == 'backspace' then
      buf:backspace()
    elseif v == 'delete' or v == 'keypad .' then
      buf:delete()
    elseif v == 'return' or v == 'keypad enter' then
      local lines = cat(buf.inp)
      buf:input(false)
      for l in lines:lines() do
        if not l:empty() then
          buf:input(l)
          buf:newline()
        end
      end
    elseif v == 'left' then
      buf:cursor(-1)
    elseif v == 'right' then
      buf:cursor(1)
    elseif v == 'home' or v == 'keypad 7' or
      (v == 'a' and input.keydown 'ctrl') then
      buf:cursor(-10000)
    elseif v == 'end' or v == 'keypad 1' or
      (v == 'e' and input.keydown 'ctrl') then
      buf:cursor(10000)
    elseif v == 'v' and input.keydown 'ctrl' then
      buf:input(sys.clipboard() or '')
    elseif v == 'c' and input.keydown 'ctrl' then
      buf:copy()
    elseif v == 'k' and input.keydown 'ctrl' then
      buf:input(false)
    elseif v == 'pageup' or v == 'keypad 9' then
      buf:scroll(-buf.lines)
    elseif v == 'pagedown' or v == 'keypad 3' then
      buf:scroll(buf.lines)
    elseif v == 'tab' then
      local t = buf:compl(cat(buf.inp))
      buf:input(false)
      buf:input(t)
    end
  elseif e == 'mousedown' or e == 'mouseup' then
    buf:click(e == 'mousedown', v, a, b)
  elseif e == 'mousemotion' then
    buf:motion()
  end
  local delay = 1/20
  local inp = e
  local tosrv
  local reply = {}
  while true do -- get all msg
    e, v = thr:read()
    if not e then
      if v then -- fatal error
        buf:write("%s\n", v)
        thr:write("quit")
        inp = true
        r = false
      end
      break
    end
    delay = 0
    v, tosrv = irc_rep(v)
    if v then
      if tosrv then
        add(reply, v)
      else
        buf:write("%s\n", v)
      end
    end
  end
  for _, v in ipairs(reply) do
    thr:write('send', v)
  end
  if inp or delay == 0 then
    buf:show()
  end
  gfx.flip(delay, true)
end
