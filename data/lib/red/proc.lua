local shell = require "red/shell"

local proc = {}

-- show the Scroll/Noscroll toggle in the command line of an output window
local function scroll_cmdline(w)
  w.cmdline = w.scroll_mode and 'Noscroll' or 'Scroll'
  w.frame:update()
end

local grep_bin = { o = true, ko = true, exe = true, a = true }

local function grep_filter(fn)
  if fn == 'red.dump' then return false end
  return not grep_bin[fn:match('%.([^.]+)$')]
end

local function grep(path, rex, err)
  for _, fn in ipairs(sys.readdir(path)) do
    local p = (path ..'/'..fn):gsub("/+", "/")
    if sys.isdir(p) then
      if not fn:startswith '.' then
        grep(p, rex, err)
      end
    elseif grep_filter(fn) then
      local f = io.open(p, "rb")
      if f then
        local nr = 0
        local epath = err:path(p) --err:path(sys.realpath(p))
        for l in f:lines() do
          nr = nr + 1
          if l:find(rex) then
            err:printf("%s:%d %s\n", epath, nr, l)
            err:scroll_output()
          end
          if nr % 1000 == 0 then
            coroutine.yield(true)
          end
        end
        f:close()
      end
      coroutine.yield(true)
    end
  end
end

local function dump(w, text)
  for i = 1, #text, 16 do
    local a = ''
    local t = string.format("%04x | ", (i - 1)/16)
    for k = 0, 15 do
      local b = string.byte(text, i + k)
      if not b then
        t = t .. string.rep('   ', 16 - k)
        break
      end
      t = t .. string.format("%02x", b) .. ' '
      if b < 32 then
        b = 46
      end
      a = a .. string.char(b)
    end
    w:printf("%s| %s\n",t, a)
  end
end

local function dump_export(w)
  local ret = {}
  for l in w:gettext():lines() do
    local hex = l:match('|(.-)|')
    if not hex then break end
    for v in hex:gmatch('%S+') do
      table.insert(ret, string.char(tonumber('0x'..v) or 32))
    end
  end
  local t = table.concat(ret, '')
  w:clear()
  dump(w, t)
  return t
end

local function dump_save(self)
  if not self.buf:isfile() then
    return
  end
  local r, e = io.file(self.buf.fname, dump_export(self) or '')
  if r then
    self:nodirty()
  else
    self.frame:err(e)
  end
  return r, e
end

function proc.dump(w)
  local data = w:data()
  if not data then return end
  w = w:output('+dump')
  w.cmd = { Get = dump_export }
  w.save = dump_save
  local s, e = data.buf:range()
  dump(w, data.buf:gettext(s, e))
  w:scroll_output()
  return true
end

function proc.grep(w, rex)
  if not rex then return end
  local data = w:data()
  local path = data and data:path() or sys.dirname(w.frame:getfilename())
  w = w:output '+grep'
  scroll_cmdline(w)
  w:tail()
  w.cwd = nil
  w:run(function() grep(path, rex, w) end)
  return true
end

local sub_delims = {
  ["/"] = true,
  [":"] = true,
}

local sub_esc = {
  ["\\t"] = "\t",
  ["\\n"] = "\n",
  ["\\r"] = "\r",
}

function proc.gsub(w, text)
  return proc.sub(w, text, true)
end

function proc.sub(w, text, glob)
  w = w:data()
  if not w then return end
  text = text:strip():gsub("\\[tnr]", sub_esc)
  local c = text:sub(1,1)
  local a
  if sub_delims[c] then
    a = text:split(c)
    table.remove(a, 1)
    if a[2] == '' and not a[3] then a[2] = false end
  else
    a = { text }
  end
  w:text_replace(function(txt, from, to)
    if glob then
      if not to then
        return txt:find(from)
      end
      txt = txt:gsub(from, to)
      return txt
    end
    if not to then
      return txt:findln(from)
    end
    local t = {}
    for l in txt:lines(true) do
      local nl = l:endswith '\n'
      if nl then
        l = l:sub(1, l:len() - 1)
      end
      l = l:gsub(from, to)
      table.insert(t, l..(nl and '\n' or ''))
    end
    return table.concat(t, '')
  end, a[1], a[2])
  return true
end

function proc.find(w, pat)
  return proc.sub(w, pat)
end

function proc.gfind(w, pat)
  return proc.gsub(w, pat)
end

local function is_space(c)
  return c == ' ' or c == '\t' or c == '\n'
end
function proc.fmt(w, width)
  width = tonumber(width) or 60
  w = w:data()
  if not w then return end
  local s, e = w.buf:range()
  local len = 0
  local t = {}
  local last
  for i = s, e do
    local c = w.buf.text[i]
    if c == '\n' and not is_space(w.buf.text[i+1])
      and not is_space(w.buf.text[i-1]) then c = ' ' end
    table.insert(t, c)
    len = len + 1
    if len >= width then
      if not last then
        table.insert(t, '\n')
        len = 0
      else
        len = #t - last
        table.insert(t, last + 1, '\n')
        last = false
      end
    elseif c == '\n' then
      len = 0
      last = false
    elseif c == ' ' or c == '\t' then
      last = #t
    end
  end
  w:text_replace(function() return table.concat(t) end)
  return true
end

function proc.par(w)
  w = w:data()
  if not w then return end
  local s, e = w.buf:range()
  local t = {}
  local c
  local i = s
  while i <= e do
    local oi = i
    while i <= #w.buf.text do
      c = w.buf.text[i]
      if c == '\t' or c == ' ' then
        i = i + 1
      else
        break
      end
    end
    if oi ~= i then
      table.append(t, ' ')
    end
    if c ~= '\n' then
      table.append(t, c)
    elseif w.buf.text[i+1] == '\n' then
      table.append(t, '\n', '\n')
    elseif oi == i then
      table.append(t, ' ')
    end
    i = i + 1
  end
  w:input(t)
  w.buf:setsel(s, s + #t)
  return true
end

proc['!'] = function(w, pat)
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

proc["dos2unix"] = function(w)
  w = w:data()
  if not w then return end
  w:text_replace(function(text)
    return (text:gsub("\r", ""))
  end)
  return true
end

local function get_tab(w)
  if w:getconf 'spaces_tab' then
    return string.rep(" ", w:getconf 'ts')
  end
  return '\t'
end

proc["i+"] = function(w)
  w = w:data()
  if not w then return end
  local tab = get_tab(w)
  w:text_replace(function(text)
    local t = ''
    for l in text:lines(true) do
      t = t .. tab .. l
    end
    return t
  end)
  return true
end

proc["i-"] = function(w)
  w = w:data()
  if not w then return end
  local tab = get_tab(w)
  w:text_replace(function(text)
    local t = ''
    for l in text:lines(true) do
      if l:startswith(tab) then
        l = l:sub(tab:len()+1)
      end
      t = t .. l
    end
    return t
  end)
  return true
end

proc['@'] = function(w, prog)
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

proc['<'] = function(w, prog)
  local out = w:output()
  if out ~= w then -- a menu writes into +Output, a window into itself
    scroll_cmdline(out)
  end
  shell.pipe(out, prog)
  return true
end

function proc.Codepoint(w)
  local data = w:data()
  if not data then return end
  local sym = data.buf.text[data:cur()]
  if not sym then return end
  local cp = utf.codepoint(sym)
  local cur = w:cur()
  w.buf:input(" "..string.format("0x%x", cp))
  w:cur(cur)
  return true
end

function proc.Line(w)
  if w.frame:main() == w.frame then -- main menu
    return
  end
  local data = w:data()
  if not data or not data.buf then return end
  local cur = w:cur()
  w.buf:input(" :"..tostring(data.buf:line_nr()))
  w:cur(cur)
  return true
end

function proc.Clear(w)
  w = w:data()
  if not w then return end
  w.buf:setsel(1, #w.buf.text + 1)
  w.buf:cut()
  w:visible()
  return true
end

function proc.cat(w, f)
  if not f then return end
  w = w:data()
  if not w then return end
  local d = io.file(w:path(f))
  if not d then return end
  local s = w:cur()
  w.buf:input(d)
  w:setsel(s, w:cur() + 1)
  return true
end

function proc.win(w)
  w = w:output "+win"
  if not w.shell then
    shell.prompt(w)
  end
  shell.win(w)
  return true
end

if PLATFORM ~= 'Windows' then
local function piped(w, out, prog)
  local ret = shell.pipe(out, prog, true)
  if not ret or not ret.fifo then
    return
  end
  local txt = w.buf:gettext(w.buf:range())
  out:run(function()
    local s = 1
    local len = txt:len()
    while s <= len and ret.fifo do
      ret.fifo:write(txt:sub(s, s + 2047))
      s = s + 2048
      coroutine.yield(true)
    end
    ret:close()
  end)
end

proc['>'] = function(w, prog)
  local data = w:data()
  if not data then return end
  local out = w:output '+Output'
  scroll_cmdline(out)
  piped(data, out, prog)
  return true
end

proc['|'] = function(w, prog)
  local data = w:data()
  if not data then return end
  local s, e = data.buf:range()
  data.buf:setsel(s, e + 1)
  piped(data, data, prog)
  return true
end
end

return proc
