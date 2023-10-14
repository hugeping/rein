local shell = require "red/shell"

local proc = {}

local function cur_skip(text, pos)
  local l = 1
  local k = 0
  while l < (pos or 1) do
    local len = utf.next(text, l)
    if len == 0 then
      break
    end
    k = k + 1
    l = l + len
  end
  return k
end

local function text_match(w, glob, fn, ...)
  local s, e = (glob and 1 or w.buf.cur), #w.buf.text
  local text = w.buf:gettext(s, e)
  local start, fin = fn(text, ...)
  if not start then
    s, e = 1, w.buf.cur
    text = w.buf:gettext(s, e)
    start, fin = fn(text, ...)
  end
  if not start then
    return
  end
  w.buf:resetsel()
  w.buf.cur = s + cur_skip(text, start)
  fin = s + cur_skip(text, fin) + 1
  w.buf:setsel(w.buf.cur, fin)
  w.buf.cur = fin
  w:visible()
end

local function text_replace(w, glob, fn, a, b)
  if a and (not w.buf:issel() or not b) then
    return text_match(w, glob, fn, a)
  end
  local s, e = w.buf:range()
  local text = w.buf:gettext(s, e)
  text = fn(text, a, b)
  w.buf:history 'start'
  w.buf:setsel(s, e + 1)
  w.buf:cut()
  w.buf:input(text)
  w.buf:history 'end'
  if not a then
    w.buf:setsel(s, w:cur()+1)
  end
  w:visible()
end

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
      grep(p, rex, err)
    elseif grep_filter(fn) then
      local f = io.open(p, "rb")
      if f then
        local nr = 0
        for l in f:lines() do
          nr = nr + 1
          if l:find(rex) then
            err:printf("%s:%d %s\n", p, nr, l)
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

function proc.dump(w)
  local data = w:winmenu()
  if not data then return end
  w = w:output('+dump')
  local s, e = data.buf:range()
  local text = data.buf:gettext(s, e)
  for i = 1, #text, 16 do
    local a, t = ''
    t = string.format("%04x | ", (i - 1)/16)
    for k = 0, 15 do
      local b = string.byte(text, i + k)
      if not b then
        for _ = k, 15 do
          t = t .. '   '
        end
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

function proc.grep(w, rex)
  if not rex then return end
  local path = w:data() and w:data():path() or
    sys.dirname(w.frame:getfilename())
  w = w:output('+grep')
  w:run(function() grep(path, rex, w) end)
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
  text_replace(w, not not glob, function(text, a, b)
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
    local t = ''
    for l in text:lines(true) do
      l = l:gsub(a, b)
      t = t .. l
    end
    return t
  end, a[1], a[2])
end

function proc.find(w, pat)
  return proc.sub(w, pat)
end

function proc.select(w, pat)
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
end

proc['!'] = function(_, pat)
  if pat:empty() then return end
  local p = thread.start(function()
    local prog = thread:read()
    if PLATFORM ~= 'Windows' then
      prog = prog .. ' &'
    end
    os.execute(prog)
  end)
  p:write(pat:unesc())
  p:detach()
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
  text_replace(w, false, function(text)
    local t = ''
    for l in text:lines(true) do
      t = t .. tab .. l
    end
    return t
  end)
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
  text_replace(w, false, function(text)
    local t = ''
    for l in text:lines(true) do
      if l:startswith(tab) then
        l = l:sub(tab:len()+1)
      end
      t = t .. l
    end
    return t
  end)
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
end

proc['<'] = function(w, prog)
  shell.pipe(w:output(), prog)
end

function proc.Codepoint(w)
  local data = w:winmenu()
  if not data then return end
  local sym = data.buf.text[data:cur()]
  local cp = utf.codepoint(sym)
  local cur = w:cur()
  w.buf:input(" "..string.format("0x%x", cp))
  w:cur(cur)
end

function proc.Line(w)
  if not w.frame.frame then -- main menu
    return
  end
  local cur = w:cur()
  w.buf:input(" :"..tostring(w.frame:win().buf:line_nr()))
  w:cur(cur)
end

function proc.Clear(w)
  w = w:winmenu()
  if not w then return end
  w.buf:setsel(1, #w.buf.text + 1)
  w.buf:cut()
  w.buf.cur = 1
  w:visible()
end

function proc.cat(w, f)
  if not f then return end
  w = w:data()
  if not w then return end
  local d = io.file(f)
  if not d then return end
  local s = w:cur()
  w.buf:input(d)
  w:setsel(s, w:cur() + 1)
end

function proc.win(w)
  w = w:output("+win")
  if not w.shell then
    shell.prompt(w)
  end
  shell.win(w)
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
    while txt ~= '' do
      ret.fifo:write(txt:sub(1, 256))
      txt = txt:sub(257)
      coroutine.yield(true)
    end
    ret.fifo:close()
    ret.fifo = nil
  end)
end

proc['>'] = function(w, prog)
  local data = w:data()
  if not data then return end
  piped(data, w:output '+Output', prog)
end

proc['|'] = function(w, prog)
  local data = w:data()
  if not data then return end
  local s, e = data.buf:range()
  data.buf:setsel(s, e + 1)
  piped(data, data, prog)
end
end

return proc
