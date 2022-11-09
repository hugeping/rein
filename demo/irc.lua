gfx.win(384, 384)
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

function win:scroll()
  local s = self
  s.line = #s.text - s.lines
  if s.line < 1 then s.line = 1 end
end

local buf = win.new()
local NICK = ARGS[4] or 'peter_irc'
local HOST = ARGS[2] or 'irc.oftc.net'
local PORT = ARGS[3] or 6667
print(HOST, PORT)
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
       print("write: ", v)
       print(s:write(v..'\r\n'))
     end
     if not s:poll() then
       thread:write(false, "Error reading from socket!")
       break
     end
     for l in s:lines() do
       print(l)
       thread:write(true, l)
     end
  end
  print("thread finished")
end)

thr:write(NICK, HOST, PORT)
buf:write("Connecting to %s:%d...",
  HOST, PORT)
buf:show() gfx.flip()

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

function win:backspace()
  local input = self.inp or ''
  local s = #input - utf.prev(input, #input)
  self.inp = input:sub(1, s)
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
    thr:write('send', buf.inp or '')
    buf.inp = ''
  end
  if thr:poll() then
    e, v = thr:read()
    buf:write(v..'\n')
    if not e then
      break
    end
  end
  buf:show()
  gfx.flip(1/20, true)
end
