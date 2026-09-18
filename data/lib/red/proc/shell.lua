-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local shell = require "red/shell"

-- show the Scroll/Noscroll toggle in the command line of an output window
local function scroll_cmdline(w)
  w.cmdline = w.scroll_mode and 'Noscroll' or 'Scroll'
  w.frame:update()
end

local function run(w, pat)
  if pat:empty() then return end
  local p = thread.start(function()
    local prog, cwd = thread:read()
    if PLATFORM ~= 'Windows' then
      if cwd then
        prog = string.format("cd %q && %s", cwd, prog)
      end
      prog = prog .. ' &'
    end
    os.execute(prog)
  end)
  p:write(pat:unesc(), w.cwd or w:getcwd())
  p:detach()
  return true
end

local function pipe_text(w, prog)
  local data = w:data()
  if not data then return end

  local tmp = os.tmpname()
  if not io.file(tmp, data.buf:gettext(data.buf:range())) then
    return
  end
  local out = w:output('+Output')
  scroll_cmdline(out)
  shell.pipe(out, prog..' '..tmp, tmp)
  return true
end

local function prog_out(prog)
  local cmd = prog:split(1, '>')
  local oname
  if #cmd == 2 then
    prog = cmd[1]:strip()
    oname = cmd[2]:strip()
  end
  return prog, oname
end

local function pipe_out(w, prog)
  local cmd, oname = prog_out(prog)
  local out = w:output(oname)
  if out ~= w then -- a menu writes into +Output, a window into itself
    scroll_cmdline(out)
  end
  shell.pipe(out, cmd)
  return true
end

local function piped(w, out, prog)
  local ret = shell.pipe(out, prog, true)
  if not ret or not ret.fifo then
    return
  end
  local posix = require "red/posix"
  local txt = w.buf:gettext(w.buf:range())

  -- the input may be large: write what fits and come back, or the
  -- editor freezes on a full pipe (and the program, on its full
  -- output, never reads again)
  posix.nonblock(ret.fifo)
  out:run(function()
    local s = 1
    local len = txt:len()
    while s <= len and ret.fifo do
      local n = posix.write(ret.fifo, txt:sub(s, s + 2047))
      if n then
        s = s + n
      elseif n == false then
        break -- the program is gone, nobody will read it
      end
      coroutine.yield(true)
    end
    ret:close()
  end)
end

local function pipe_window(w, prog)
  local cmd, oname = prog_out(prog)
  local data = w:data()
  if not data then return end
  local out = w:output()
  scroll_cmdline(out)
  piped(data, out, cmd)
  return true
end

local function pipe_edit(w, prog)
  local data = w:data()
  if not data then return end
  local s, e = data.buf:range()
  data.buf:setsel(s, e + 1)
  piped(data, data, prog)
  return true
end

local shell_proc = {
  ["!"] = run,
  ["@"] = pipe_text,
  ["<"] = pipe_out,
}

if PLATFORM ~= 'Windows' then
  shell_proc['>'] = pipe_window
  shell_proc['|'] = pipe_edit
end

return shell_proc
