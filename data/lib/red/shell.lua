local shell = {}

local function pipe_shell()
  local posix = require("red/posix")
  local poll, sighup = posix.poll, posix.sighup
  local poll_mode = not not poll
  poll = poll or function() return true end
  local function read_sym(f)
    local t, b = '', ''
    while b and (t == '' or t:byte(#t) >= 128) do
      while b and poll(f) do
        b = f:read(1)
        if not b then break end
        t = t .. b
        if (not poll_mode or t:len() > 256) and
          b:byte(1) < 128 then b = false end
      end
    end
    return t ~= '' and t
  end
  local prog, cwd = thread:read()
  if cwd then
    prog = string.format("cd %q && %s", cwd, prog)
  end
  sighup(true)
  local f, e = io.popen(prog, "r")
  sighup(false)
  thread:write(not not f, e)
  if not f then return end
  f:setvbuf 'no'
  local t = true
  while t do
    t = read_sym(f)
    if t then
      thread:write(t)
    end
  end
  f:close()
  thread:write '\1eof'
end

local function pipe_proc()
  require "std"
  local sighup = require("red/posix").sighup
  local prog = thread:read()
  sighup(true)
  local f, e = io.popen(prog, "r")
  sighup(false)
  thread:write(not not f, e)
  if not f then return end
  f:setvbuf 'no'
  local pre
  while true do
    local chunk = f:read(512)
    if not chunk then
      if pre then
        thread:write(pre)
      end
      break
    end
    chunk = (pre or '') .. chunk
    pre = nil
    for l in chunk:lines(true) do
      if not l:endswith '\n' then
        pre = l
        break
      end
      thread:write(l)
    end
  end
  f:close()
  thread:write '\1eof'
end

function shell.pipe(w, prog, inp, sh)
  local tmp
  if prog:empty() then
    return
  end
  if PLATFORM ~= 'Windows' and inp == true then
    tmp = os.tmpname()
    os.remove(tmp)
    if not os.execute("mkfifo "..tmp) then
      return
    end
    prog = string.format("eval %q", prog)
    prog = '( ' ..prog.. ' ) <' .. (inp and tmp or '/dev/null') .. ' 2>&1'
  elseif type(inp) == 'string' then
    tmp = inp
  end
  local p = thread.start(sh and pipe_shell or pipe_proc)
  local ret = { }
  p:write(prog, w.cwd or false)
  local r, e = p:read()
  if not r then
    w:input(e..'\n')
    return
  end
  if tmp then
    ret.fifo = io.open(tmp, "a")
    ret.fifo:setvbuf 'no'
  end
  w.output_pos = w:cur()
  r = w:run(function()
    w:history 'start'
    local l
    while l ~= '\1eof' and not ret.stopped do
      local data
      while p:poll() do
        l = p:read()
        data = true
        if l == '\1eof' then
          break
        end
        if sh then
          w.buf:append(l, true)
          w.output_pos = w:cur()
        else
          local c = w:cur(w.output_pos)
          w.buf:input(l)
          w.output_pos = w:cur(c)
        end
      end
      coroutine.yield(inp ~= true or data)
    end
    if sh then
      shell.prompt(w)
    else
      w:cur(w.output_pos)
    end
    w:history 'end'
    if tmp then
      os.remove(tmp)
    end
    ret.stopped = true
    if ret.fifo then
      ret.fifo:close()
      ret.fifo = nil
    end
    p:wait()
  end)
  ret.routine = r
  r.kill = function()
    if ret.fifo then
      ret.fifo:close()
      ret.fifo = nil
    end
    if not ret.stopped then
      p:err("kill")
      p:detach()
      ret.stopped = true
    end
  end
  return ret
end

function shell:delete()
  if not self.prog or
    not self.prog.routine or
    self.prog.stopped then
    return
  end
  self.prog.routine.kill()
  self.prog.stopped = true
end

function shell:escape()
  if not self.prog or self.prog.stopped or
    not self.prog.fifo then
    return self.super.escape(self)
  end
  self.prog.fifo:close()
  self.prog.fifo = nil
end

function shell:prompt()
  self.buf:append('$ ', true)
  self.output_pos = self:cur()
end

function shell:execute(t)
 local cmd = t:split(1)
 if self.prog and not self.prog.stopped then
    if self.prog.fifo then
      self.prog.fifo:write(t..'\n')
      self.prog.fifo:flush()
    end
  elseif cmd[1] == 'cd' and #cmd == 2 then
    cmd[2] = cmd[2]:unesc()
    local cwd = (self.cwd or '.').. '/' .. cmd[2]
    if sys.is_absolute_path(cmd[2]) then
      cwd = cmd[2]
    end
    if not sys.isdir(cwd) then
      self.buf:input("Error\n")
    else
      self.cwd = sys.realpath(cwd) .. '/'
      self.buf:input(self.cwd..'\n')
    end
    shell.prompt(self)
  elseif cmd[1] == 'ls' then
    self:readdir(self:path(cmd[2] or './'))
    shell.prompt(self)
  elseif cmd[1] == 'pwd' then
    self.buf:input(sys.realpath(self:path() or './')..'\n')
    shell.prompt(self)
  elseif t:empty() then
    shell.prompt(self)
  else
    self.prog = shell.pipe(self, t, true, true)
  end
end

function shell:newline()
  if not self.output_pos or self.output_pos > #self.buf.text + 1 then
    self.buf:append "\n"
    shell.prompt(self)
    return
  end
  if self:cur() < self.output_pos then
    return self.super.newline(self)
  end
  self:cur(self.output_pos)
  local t = ''
  for i = self.buf.cur, #self.buf.text do
    if self.buf.text[i] == '\n' then
      break
    end
    t = t .. self.buf.text[i]
  end
  self.buf:tail()
  self.buf:input '\n'
  self.output_pos = self.buf.cur
  local h = self.shell.hist
  if h[#h] ~= t then
    table.insert(h, t)
    if #h > 256 then
      table.remove(h, 1)
    end
    h.pos = #h + 1
  end
  shell.execute(self, t)
end

function shell:up()
  if not input.keydown 'ctrl' or not self.output_pos then
    return self.super.up(self)
  end
  local h = self.shell.hist
  if not h.pos or h.pos == 1 then return end
  h.pos = h.pos - 1
  local t = h[h.pos]
  self:cur(self.output_pos)
  self.buf:kill()
  self.buf:input(t)
end

function shell:down()
  if not input.keydown 'ctrl' or not self.output_pos then
    return self.super.down(self)
  end
  local h = self.shell.hist
  if not h.pos then return end
  h.pos = h.pos + 1
  local t = h[h.pos]
  self:cur(self.output_pos)
  self.buf:kill()
  self.buf:input(t or '')
  h.pos = math.min(#h + 1, h.pos)
end

function shell.win(w)
  w.shell = { hist = {} }
  w.super = { up = w.up, down = w.down,
    newline = w.newline, escape = w.escape }
  w.newline = shell.newline
  w.escape = shell.escape
  w.delete = shell.delete
  w.up = shell.up
  w.down = shell.down
  w.conf.ts = 8
end

return shell
