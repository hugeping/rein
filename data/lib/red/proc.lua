local shell = require "red/shell"

local proc = {}

local function grep_filter(fn)
  if fn == 'red.dump' then return false end
  local ext = { 'o', 'ko', 'exe', 'a' }
  for _, v in ipairs(ext) do
    if fn:endswith('.'..v) then return false end
  end
  return true
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
        local path = err:path(p) --err:path(sys.realpath(p))
        for l in f:lines() do
          nr = nr + 1
          if l:find(rex) then
            err:printf("%s:%d %s\n", path, nr, l)
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
    local a, t = ''
    t = string.format("%04x | ", (i - 1)/16)
    for k = 0, 15 do
      local b = string.byte(text, i + k)
      if not b then
        t = t .. string.rep('   ', 15 - k + 1)
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
  local t = w:gettext()
  local ret = {}
  for l in t:lines() do
    l = l:split('|', 2)
    if not l[2] then break end
    l = l[2]:split()
    for _, v in ipairs(l) do
      if not v:empty() then
        table.insert(ret, string.char(tonumber('0x'..v) or 32))
      end
    end
  end
  t = table.concat(ret, '')
  w:clear()
  dump(w, t)
  return t
end

local function dump_save(self)
  if not self.buf:isfile() then
    return
  end
  local r, e = io.file(self.buf.fname, dump_export(self) or '')
  self.buf:dirty(false)
  if r then
    self:nodirty()
  else
    self.frame:err(e)
  end
  return r, e
end

function proc.dump(w)
  local data = w:winmenu()
  if not data then return end
  w = w:output('+dump')
  w.cmd = { Get = dump_export }
  w.save = dump_save
  local s, e = data.buf:range()
  local text =
  dump(w, data.buf:gettext(s, e))
  return true
end

function proc.grep(w, rex)
  if not rex then return end
  local path = w:data() and w:data():path() or
    sys.dirname(w.frame:getfilename())
  w = w:output '+grep'
  w:tail()
  w.cwd = nil
  w:run(function() grep(path, rex, w) end)
  return true
end

--luacheck: push
--luacheck: ignore 432
local sub_delims = {
  ["/"] = true,
  [":"] = true,
}

function proc.gsub(w, text)
  return proc.sub(w, text, true)
end

function proc.sub(w, text, glob)
  w = w:winmenu()
  if not w then return end
  text = text:strip():gsub("\\[tnr]", { ["\\t"] = "\t", ["\\n"] = "\n", ["\\r"] = "\r" })
  local c = text:sub(1,1)
  local a
  if sub_delims[c] then
    a = text:split(c)
    table.remove(a, 1)
    if a[2] == '' and not a[3] then a[2] = false end
  else
    a = { text }
  end
  w:text_replace(function(text, a, b)
    if glob then
      if not b then
        return text:find(a)
      end
      text = text:gsub(a, b)
      return text
    end
    if not b then
      return text:findln(a)
    end
    local t = {}
    for l in text:lines(true) do
      local nl = l:endswith '\n'
      if nl then
        l = l:sub(1, l:len() - 1)
      end
      l = l:gsub(a, b)
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
  w = w:winmenu()
  if not w then return end
  local s, e = w.buf:range()
  local b = {}
  local len = 0
  local t = {}
  local c, last
  for i = 1, #w.buf.text do
    c = w.buf.text[i]
    if i >= s and i <= e then
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
    else
      table.insert(b, c)
    end
  end
  w:history 'start'
  w:history('cut', s, e - s + 1)
  w:set(b)
  w:cur(s)
  w:input(t)
  w:history 'end'
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
  p:write(pat:unesc(), w.cwd)
  p:detach()
  return true
end

proc["dos2unix"] = function(w)
  w = w:winmenu()
  if not w then return end
  w:text_replace(function(text)
    local t = text:gsub("\r", "")
    return t
  end)
  return true
end

proc["i+"] = function(w)
  w = w:winmenu()
  if not w then return end
  local ts = w:getconf 'ts'
  local tab_sp = w:getconf 'spaces_tab'
  local tab = '\t'
  if tab_sp then
    tab = string.rep(" ", ts)
  end
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
  w = w:winmenu()
  if not w then return end
  local ts = w:getconf 'ts'
  local tab_sp = w:getconf 'spaces_tab'
  local tab = '\t'
  if tab_sp then
    tab = string.rep(" ", ts)
  end
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
  local f = io.open(tmp, "wb")
  if not f then
    return
  end
  f:write(data.buf:gettext(data.buf:range()))
  f:close()
  shell.pipe(w:output('+Output'), prog..' '..tmp, tmp)
  return true
end

proc['<'] = function(w, prog)
  shell.pipe(w:output(), prog)
  return true
end

function proc.Codepoint(w)
  local data = w:winmenu()
  if not data then return end
  local sym = data.buf.text[data:cur()]
  local cp = utf.codepoint(sym)
  local cur = w:cur()
  w.buf:input(" "..string.format("0x%x", cp))
  w:cur(cur)
  return true
end

function proc.Line(w)
  if not w.frame.frame then -- main menu
    return
  end
  local cur = w:cur()
  w.buf:input(" :"..tostring(w.frame:win().buf:line_nr()))
  w:cur(cur)
  return true
end

function proc.Clear(w)
  w = w:winmenu()
  if not w then return end
  w.buf:setsel(1, #w.buf.text + 1)
  w.buf:cut()
  w.buf.cur = 1
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

--luacheck: pop

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
    while s <= txt:len() and ret.fifo do
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
  piped(data, w:output '+Output', prog)
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
