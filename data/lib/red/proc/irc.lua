-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
--
-- A minimal IRC client for red:
--
--   irc [tls://][nick@]host[:port][/#channel]
--
-- opens (or reuses) the "+irc" window.  The default is TLS on 6697;
-- any other port is plain TCP unless it is written as "tls://host:port".
-- The socket lives in a thread of its own and the window coroutine
-- collects its lines, so the editor keeps running while the connection
-- is made and read.
--
-- Typed text goes to the current channel (or query target) as PRIVMSG.
-- /join /part /nick /msg /query /me /topic /quit are understood; any
-- other /command is sent as it is (without the slash).  The nick comes
-- from "nick@" or $USER, /nick changes it; tab (and ctrl-f) completes
-- the names seen.  Get reconnects, red.dump keeps the window (it is not
-- connected back automatically).
local win = require "red/win"

local irc = {}

local function default_nick()
  local n = os.getenv 'USER'

  if not n or n == '' then
    n = os.getenv 'LOGNAME'
  end
  if not n or n == '' then
    n = 'rein'
  end
  return (n:gsub('[^%w_%-]', '_'))
end

-- The socket half, in a thread of its own: reading the server must not
-- block the editor.  thread.start serializes the function, so the body
-- may not use upvalues (sock is required inside it).
local function thread_run()
  local sock = require "sock"
  local host, port, tls, nick = thread:read()
  local s, e = sock.dial(host, port, tls and host or nil)
  local pend = {}
  -- the socket is non-blocking, so without a pause the loop below
  -- would spin and burn a core; the pause paces the socket checks and
  -- the commands (a local of the body: thread.start refuses functions
  -- with upvalues)
  local DELAY = 1/30

  -- the channel is half duplex: a write is refused while the window is
  -- writing, so keep the lines and send them when it reads
  local function put(l)
    if not pcall(thread.write, thread, l) then
      table.insert(pend, l)
    end
  end

  -- report the end of the connection and stay until the window takes
  -- the message, so that its poll() never sees a dead peer
  local function finish(err)
    while thread:poll(0) do -- let the window finish its pending write
      thread:read()
    end
    -- the channel is half duplex, so the window may be writing right
    -- now: wait for it, but not forever, it may be gone already (the
    -- window was closed and nobody will read the message)
    while pcall(thread.poll, thread, 0) do
      if pcall(thread.write, thread, false, err) then
        break
      end
      sys.sleep(DELAY)
    end
    pcall(function()
      while thread:read() ~= 'quit' do end
    end)
  end

  if not s then
    finish(e or 'cannot connect')
    return
  end
  s:write(string.format('NICK %s\r\nUSER %s 0 * :%s\r\n',
    nick, nick, nick))

  while true do
    while thread:poll() do
      local c, v = thread:read()

      if c == 'quit' then
        pcall(function() s:write('QUIT :bye\r\n') end)
        s:close()
        finish()
        return
      elseif c == 'send' then
        if not s:write(v .. '\r\n') then
          s:close()
          finish 'send failed'
          return
        end
      end
    end
    if pend[1] then -- what the window refused is tried again
      local l = table.remove(pend, 1)

      if not pcall(thread.write, thread, l) then
        table.insert(pend, 1, l)
        sys.sleep(DELAY)
      end
    end
    -- tcp:poll is false on a close or an error, a number otherwise;
    -- tcp:lines takes the ready lines (and strips \r) out of it
    local ok, err = s:poll()

    if not ok then
      s:close()
      finish(err or 'connection closed')
      return
    end
    local data

    for l in s:lines() do
      put(l)
      data = true
    end
    if not data then
      sys.sleep(DELAY)
    end
  end
end

local function split_prefix(line)
  if not line:startswith ':' then
    return nil, line
  end
  local s = line:find(' ', 1, true)

  if not s then
    return line:sub(2), ''
  end
  return line:sub(2, s - 1), line:sub(s + 1)
end

-- "middle params :trailing" -> "middle params", "trailing"
local function split_params(s)
  if s:startswith ':' then
    return '', s:sub(2)
  end
  local p = s:find(' :', 1, true)

  if p then
    return s:sub(1, p - 1), s:sub(p + 2)
  end
  return s, ''
end

-- services like NickServ mark their text with the mIRC formatting
-- codes: \2 bold, \3[fg[,bg]] and \4[hex] colors, \17 italic, \1f
-- underline, \f reset, ...  The buffer is plain text, so the color
-- codes take their numbers with them and the rest just go away
local function plain(s)
  if not s:find('%c') then
    return s
  end
  s = s:gsub('\3%d*,?%d*', ''):gsub('\4%x*,?%x*', '')
  return (s:gsub('%c', ''))
end

-- add to the window text keeping the line the user has typed but not
-- sent yet (as the win-shell does); the view follows the tail when
-- scroll mode is on
local function say(w, text)
  local e = w.irc
  local s = e.output_pos
  local tail, off

  if s and s <= #w.buf.text then
    tail = w.buf:gettext(s, #w.buf.text)
    off = math.max(0, w.buf.cur - s)
    w.buf:setsel(s, #w.buf.text + 1)
    w.buf:cut(false)
  end
  w.buf:append(text, true)
  e.output_pos = w.buf.cur
  if tail then
    w.buf:append(tail)
    w.buf.cur = math.min(e.output_pos + off, #w.buf.text + 1)
  end
  w:scroll_output()
end

local function why(s)
  if s and s ~= '' then
    return ' (' .. s .. ')'
  end
  return ''
end

-- the parameters of a command for display: middle and trailing are
-- joined as the protocol has them
local function args(middle, trailing)
  if trailing == '' then
    return middle
  end
  if middle == '' then
    return trailing
  end
  return middle .. ' ' .. trailing
end

-- a message to a channel other than the current one is marked with it
local function tag(e, target)
  if target and target ~= e.nick and target ~= e.chan and
    target:find('^[#&+!]') then
    return '[' .. target .. '] '
  end
  return ''
end

-- the channel is half duplex: a write is refused while the thread is
-- writing, so the command waits for a quiet moment
local function flush(w)
  local e = w.irc

  while e.thr and e.queue[1] do
    if not pcall(e.thr.write, e.thr, 'send', e.queue[1]) then
      return
    end
    table.remove(e.queue, 1)
  end
end

function irc.send(w, cmd)
  local e = w.irc

  if not e.thr then
    say(w, '* not connected\n')
    return false
  end
  table.insert(e.queue, cmd)
  flush(w)
  return true
end

local function number(w, cmd, middle, trailing)
  local e = w.irc

  if cmd == '353' then -- NAMES: "srv 353 me = #chan :@op nick"
    local chan = middle:match('[#&+!]%S+') or middle

    for n in trailing:gmatch('%S+') do
      e.nicks[(n:gsub('^[@+]', ''))] = true
    end
    say(w, string.format('* %s: %s\n', chan, trailing))
    return
  end
  if cmd == '332' then -- TOPIC: "srv 332 me #chan :the topic"
    local chan = middle:match('[#&+!]%S+') or middle

    say(w, string.format('* topic %s: %s\n', chan, trailing))
    return
  end
  say(w, string.format('* %s %s\n', cmd,
    trailing ~= '' and trailing or middle))
end

-- a server line into the window text
function irc.line(w, l)
  local e = w.irc
  local prefix, rest = split_prefix(l)

  if not rest or rest == '' then
    return
  end
  local cmd, params = rest:match('^(%S+)%s*(.*)$')

  if not cmd then
    return
  end
  local nick = prefix and prefix:match('^([^!]+)') or nil
  local middle, trailing = split_params(params)

  if nick then
    e.nicks[nick] = true
  end
  if cmd == 'PING' then
    irc.send(w, 'PONG :' .. (trailing ~= '' and trailing or middle))
    return
  end
  if (cmd == 'PRIVMSG' or cmd == 'NOTICE') and
    nick and nick == e.nick then
    return -- the server echoes our own messages back
  end
  if trailing:startswith '\1' then
    local t, a = trailing:match('^\1(%S+)%s*(.-)\1$')

    if t == 'ACTION' and nick and cmd == 'PRIVMSG' then
      say(w, string.format('* %s %s\n', nick, plain(a)))
    end
    return -- other ctcp is not shown
  end
  middle, trailing = plain(middle), plain(trailing)
  if cmd == 'PRIVMSG' or cmd == 'NOTICE' then
    local text = trailing

    if cmd == 'NOTICE' then
      say(w, string.format('-%s- %s\n', nick or middle, text))
    else
      say(w, string.format('%s%s: %s\n', tag(e, middle),
        nick or middle, text))
    end
  elseif cmd == 'JOIN' then
    -- the channel is a trailing parameter (":nick JOIN :#chan")
    local chan = middle ~= '' and middle or trailing

    say(w, string.format('* %s joined %s\n', nick, chan))
    if nick == e.nick and not e.chan then
      e.chan = chan
    end
  elseif cmd == 'PART' then
    say(w, string.format('* %s left %s%s\n', nick, middle, why(trailing)))
  elseif cmd == 'QUIT' then
    say(w, string.format('* %s quit%s\n', nick, why(trailing)))
  elseif cmd == 'NICK' then
    -- the new nick may come as a middle parameter (":a!u@h NICK b")
    local new = trailing ~= '' and trailing or middle

    say(w, string.format('* %s is now %s\n', nick, new))
    if nick == e.nick and new ~= '' then
      e.nick = new
    end
  elseif cmd == 'KICK' then
    local chan, who = middle:match('^(%S+)%s+(%S+)')

    say(w, string.format('* %s kicked %s from %s%s\n', nick, who,
      chan, why(trailing)))
  elseif cmd == 'TOPIC' then
    say(w, string.format('* topic %s: %s\n', middle, trailing))
  elseif cmd == 'MODE' then
    say(w, string.format('* mode %s\n', args(middle, trailing)))
  elseif cmd:match('^%d%d%d$') then
    if cmd == '001' then
      e.ready = true
      if e.pending_join then
        irc.send(w, 'JOIN ' .. e.pending_join)
        e.pending_join = nil
      end
    end
    number(w, cmd, middle, trailing)
  else
    say(w, string.format('* %s %s\n', cmd, args(middle, trailing)))
  end
end

-- a typed line: "/command args" or a message to the current target
function irc.execute(w, t)
  local e = w.irc
  local cmd, arg = t:match('^/(%S+)%s*(.*)$')

  if not cmd then
    if not e.chan then
      say(w, '* no target: /join #channel or /query nick\n')
      return
    end
    if irc.send(w, 'PRIVMSG ' .. e.chan .. ' :' .. t) then
      say(w, string.format('%s: %s\n', e.nick, t))
    end
    return
  end
  cmd = cmd:lower()
  if cmd == 'join' then
    local chan, key = arg:match('^(%S+)%s*(%S*)')

    if not chan then
      say(w, '* usage: /join #channel [key]\n')
      return
    end
    if e.ready then
      if not irc.send(w, 'JOIN ' .. chan ..
        (key ~= '' and (' ' .. key) or '')) then
        return
      end
    end
    e.chan = chan
    e.pending_join = not e.ready and chan or nil
  elseif cmd == 'part' then
    local chan, reason = arg:match('^(%S*)%s*(.*)$')

    chan = chan ~= '' and chan or e.chan
    if not chan then
      say(w, '* usage: /part [#channel] [reason]\n')
      return
    end
    if irc.send(w, 'PART ' .. chan ..
      (reason ~= '' and (' :' .. reason) or '')) then
      if chan == e.chan then
        e.chan = nil
      end
    end
  elseif cmd == 'nick' then
    if arg == '' then
      say(w, '* usage: /nick name\n')
      return
    end
    if irc.send(w, 'NICK ' .. arg) then
      e.nick = arg
    end
  elseif cmd == 'msg' then
    local who, text = arg:match('^(%S+)%s+(.*)$')

    if not who then
      say(w, '* usage: /msg nick text\n')
      return
    end
    if irc.send(w, 'PRIVMSG ' .. who .. ' :' .. text) then
      say(w, string.format('%s: %s\n', e.nick, text))
    end
  elseif cmd == 'query' then
    if arg == '' then
      say(w, '* usage: /query nick\n')
      return
    end
    e.chan = arg
  elseif cmd == 'me' then
    if not e.chan then
      say(w, '* no target: /join #channel first\n')
      return
    end
    if irc.send(w, 'PRIVMSG ' .. e.chan ..
      ' :\1ACTION ' .. arg .. '\1') then
      say(w, string.format('* %s %s\n', e.nick, arg))
    end
  elseif cmd == 'topic' then
    if not e.chan then
      say(w, '* no target\n')
      return
    end
    irc.send(w, 'TOPIC ' .. e.chan .. ' :' .. arg)
  elseif cmd == 'quit' then
    if irc.send(w, 'QUIT :' .. (arg ~= '' and arg or 'bye')) then
      say(w, '* quitting\n')
    end
  elseif cmd == 'raw' then
    irc.send(w, arg)
  else
    irc.send(w, t:sub(2)) -- any other command goes as it is
  end
end

-- the window half: collect the lines of the thread into the buffer
local function pump(w, p)
  return function()
    local e = w.irc

    while true do
      local ok, more = pcall(p.poll, p)

      if not ok then
        say(w, string.format('* connection lost: %s\n',
          tostring(more)))
        break
      end
      if not more then
        flush(w)
        if e.queue[1] then
          coroutine.yield(true) -- keep looking for a quiet moment
        else
          coroutine.yield()
        end
      else
        local m, err = p:read()

        if m == false then
          say(w, string.format('* disconnected%s\n',
            err and (': ' .. tostring(err)) or ''))
          break
        elseif m ~= true then
          irc.line(w, m)
        end
        flush(w)
      end
    end
    pcall(p.write, p, 'quit')
    if e.thr == p then -- not superseded by a reconnect
      e.queue = {}
      e.thr, e.pump = nil, nil
      w.cmdline = 'Connect ' ..
        (w.scroll_mode and 'Noscroll' or 'Scroll')
      w.frame:update()
    end
  end
end

function irc.connect(w, host, port, tls)
  local e = w.irc

  e.host, e.port, e.tls = host, port, tls
  if not e.nick or e.nick == '' then
    e.nick = default_nick()
  end
  e.nicks[e.nick] = true
  e.ready = nil
  e.queue = {}
  e.pending_join = e.chan -- rejoin the channel after a reconnect
  say(w, string.format('* connecting to %s:%d%s...\n', host, port,
    tls and ' (tls)' or ''))
  if e.thr then
    pcall(e.thr.write, e.thr, 'quit')
  end
  local p = thread.start(thread_run)

  e.thr = p
  p:write(host, port, tls or false, e.nick)
  local r = w:run(pump(w, p))

  r.kill = function()
    pcall(p.write, p, 'quit')
  end
  e.pump = r
  w.cmdline = 'Noscroll'
  w.frame:update()
end

local function connect_cmd(w)
  local w_irc = w.irc

  if w_irc.thr then
    say(w, '* already connected\n')
  elseif w_irc.host then
    irc.connect(w, w_irc.host, w_irc.port, w_irc.tls)
  end
  return true
end

function irc:Get()
  local e = self.irc

  if e.thr or not e.host then
    return true
  end
  irc.connect(self, e.host, e.port, e.tls)
  return true
end

-- return in the body sends the typed line (as in the win-shell)
function irc:newline()
  local e = self.irc
  local pos = e.output_pos

  if not pos or pos > #self.buf.text + 1 then
    self.buf:append '\n'
    e.output_pos = #self.buf.text + 1
    self:scroll_output()
    return
  end
  if self.buf.cur < pos then -- editing the log, not the input line
    return self.super.newline(self)
  end
  local n, ep = #self.buf.text, #self.buf.text + 1
  local t = ''

  for i = pos, n do
    if self.buf.text[i] == '\n' then
      ep = i
      break
    end
    t = t .. self.buf.text[i]
  end
  -- the line itself goes away: it stays in the formatted echo only
  self.buf:setsel(pos, ep)
  self.buf:cut(false)
  e.output_pos = ep > n and pos or (pos + 1)
  t = t:strip()
  if t ~= '' then
    local h = e.hist

    if h[#h] ~= t then
      table.insert(h, t)
      if #h > 256 then
        table.remove(h, 1)
      end
    end
    e.pos = #h + 1
    irc.execute(self, t)
  end
  self:scroll_output()
end

-- recall a line of the input history; the selected history entry is
-- not the "typed" text, so clear the selection first.  The view is not
-- moved at all: the recalled line is at the cursor, where the user has
-- typed before
local function history(w, step)
  local e = w.irc
  local pos = e.pos + step

  if pos < 1 or pos > #e.hist + 1 then
    return
  end
  e.pos = pos
  w:resetsel()
  w:cur(e.output_pos)
  w.buf:kill()
  w.buf:input(e.hist[pos] or '')
end

function irc:up()
  if not input.keydown 'ctrl' or not self.irc.output_pos then
    return self.super.up(self)
  end
  return history(self, -1)
end

function irc:down()
  if not input.keydown 'ctrl' or not self.irc.output_pos then
    return self.super.down(self)
  end
  return history(self, 1)
end

function irc:keydown_event(v)
  if v == 'tab' then
    return self:compl(irc.completion)
  end
  return win.keydown_event(self, v)
end

-- the names seen, for tab and ctrl-f completion
function irc.completion(w, txt)
  local res = {}

  if txt == '' then
    return res
  end
  local lt = txt:lower()
  for n in pairs(w.irc.nicks) do
    if n:lower():startswith(lt) and n ~= txt then
      -- keep the case the user typed, complete the rest of the name
      table.insert(res, txt .. n:sub(#txt + 1))
    end
  end
  table.sort(res)
  return res
end

-- set a window up as an irc window: the input line, completion, the
-- connection commands and dump
function irc.win(w)
  local e = w.irc

  if not e then
    e = { nicks = {}, hist = {}, pos = 1, queue = {} }
    w.irc = e
    w.scroll_mode = true
    -- the scheme and the wrapping are the window's, not its name's:
    -- a rename re-reads the presets, these stay
    w.kind_conf = { syntax = 'irc', wrap = true }
    w.dump = irc.dump
    w.cmd = setmetatable({ Connect = connect_cmd },
      { __index = win.cmd })
    w.super = { up = w.up, down = w.down, newline = w.newline }
    w.newline = irc.newline
    w.up = irc.up
    w.down = irc.down
    w.keydown_event = irc.keydown_event
    w.completion = irc.completion
    w.Get = irc.Get
  end
  e.output_pos = e.output_pos or (#w.buf.text + 1)
  w.cmdline = (e.thr and '' or 'Connect ') ..
    (w.scroll_mode and 'Noscroll' or 'Scroll')
  w.frame:update()
  return w
end

function irc:dump()
  local d = win.dump(self)

  d.type = 'irc'
  d.host = self.irc.host
  d.port = self.irc.port
  d.tls = self.irc.tls
  d.nick = self.irc.nick
  d.chan = self.irc.chan
  d.hist = self.irc.hist
  d.output_pos = self.irc.output_pos
  return d
end

win.kinds.irc = function(fr, d, idx)
  local w = win.kinds.win(fr, d, idx)

  if not w then return end
  irc.win(w)
  w.irc.host, w.irc.port, w.irc.tls = d.host, d.port, d.tls
  w.irc.nick, w.irc.chan = d.nick, d.chan
  w.irc.hist = d.hist or {}
  w.irc.pos = #w.irc.hist + 1
  w.irc.output_pos = d.output_pos or (#w.buf.text + 1)
  if w.irc.nick then
    w.irc.nicks[w.irc.nick] = true
  end
  w.cmdline = 'Connect ' ..
    (w.scroll_mode and 'Noscroll' or 'Scroll')
  w:cur(#w.buf.text + 1)
  w.frame:update()
  return w
end

-- "[tls://][nick@]host[:port][/#channel]": 6697 is the default and is
-- TLS, any other port is plain TCP unless "tls://" is given; "irc://"
-- at the beginning is ignored, so a pasted irc url works
function irc.parse(spec)
  local t = spec:match('^%s*(%S+)%s*$')

  if not t then
    return
  end
  if t:find('^irc://') then
    t = t:sub(7)
  end
  local tls
  if t:find('^tls://') then
    tls = true
    t = t:sub(7)
  end
  local nick, rest = t:match('^([^@/]+)@(.+)$')

  if nick then
    t = rest
  end
  local host, port, chan = t:match('^([^:/]+):?(%d*)/?(.*)$')

  if not host or host == '' then
    return
  end
  port = tonumber(port)
  if not port then
    port, tls = 6697, true
  elseif port == 6697 then
    tls = true
  elseif tls == nil then
    tls = false
  end
  return host, port, tls, (chan ~= '' and chan or nil), nick
end

-- "irc [tls://][nick@]host[:port][/#channel]"
local function irc_proc(w, target)
  local out = w:output "+irc"

  irc.win(out)
  local host, port, tls, chan, nick = irc.parse(target or '')

  if not host then
    say(out, '* usage: irc [tls://][nick@]host[:port][/#channel]\n')
    out:scroll_output()
    return true
  end
  if out.irc.thr and out.irc.host == host and
    out.irc.port == port and out.irc.tls == tls then
    if nick and nick ~= out.irc.nick then
      out.irc.nick = nick
      irc.send(out, 'NICK ' .. nick)
    end
    if chan and chan ~= out.irc.chan then
      out.irc.chan = chan
      if out.irc.ready then
        irc.send(out, 'JOIN ' .. chan)
      else
        out.irc.pending_join = chan
      end
    end
    out:scroll_output()
    return true
  end
  if nick then
    out.irc.nick = nick
  end
  if chan then
    out.irc.chan = chan
  end
  irc.connect(out, host, port, tls)
  return true
end

return {
  irc = irc_proc,
}
