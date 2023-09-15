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

local function grep(path, rex, err)
  for _, fn in ipairs(sys.readdir(path)) do
    local p = (path ..'/'..fn):gsub("/+", "/")
    if sys.isdir(p) then
      grep(p, rex, err)
    else
      local f = io.open(p, "rb")
      if f then
        local nr = 0
        for l in f:lines() do
          nr = nr + 1
          if l:find(rex) then
            err:printf("%s:%d %q\n", p, nr, l)
          end
          if nr % 1000 == 0 then
            coroutine.yield()
          end
        end
        f:close()
      end
      coroutine.yield()
    end
  end
end

function proc.grep(w, rex)
  w = w:output('+Output')
  w:run(function()
    grep(sys.dirname(w.frame:getfilename()), rex, w)
  end)
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
  text = text:strip():gsub("\\[tn]", { ["\\t"] = "\t", ["\\n"] = "\n" })
  local c = text:sub(1,1)
  local a
  if sub_delims[c] then
    a = text:split(c)
    table.remove(a, 1)
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
  os.execute(pat:unesc())
end

local function pipe(w, prog, tmp, sh)
  if tmp then prog = 'cat '..tmp.. ' | '.. prog end
  if PLATFORM ~= 'Windows' then
    prog = '( ' ..prog .. ' ) </dev/null 2>&1'
  end
  local p = thread.start(function()
    local prog = thread:read()
    local f = io.popen(prog, "r")
    if f then
      for l in f:lines() do
        thread:write(l)
      end
      f:close()
    end
    thread:write '\1eof'
  end, prog, tmp)
  local r = w:run(function()
    w:history 'start'
    local l
    p:write(prog)
    while l ~= '\1eof' do
      while p:poll() do
        l = p:read()
        if l == '\1eof' then
          break
        end
        w.buf:input(l..'\n')
      end
      coroutine.yield()
    end
    if sh then
      w:input '$ '
    end
    w:history 'end'
    if tmp then
      os.remove(tmp)
    end
  end)
  r.kill = function()
    p:detach()
  end
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

proc['>'] = function(w, prog)
  local data = w:data()
  if not data then return end

  local tmp = os.tmpname()
  local f = io.open(tmp, "wb")
  if not f then
    return
  end
  f:write(data.buf:gettext(data.buf:range()))
  f:close()
  pipe(w:output('+Output'), prog..' '..tmp, tmp)
end

proc['<'] = function(w, prog)
  pipe(w:output(), prog)
end

function proc.Codepoint(w)
  local data = w:winmenu()
  if not data then return end
  local sym = data.buf.text[data:cur()]
  local cp = utf.codepoint(sym)
  local cur = w:cur()
  w.buf:input(" "..string.format("%x", cp))
  w:cur(cur)
end

function proc.Getline(w)
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

function win_newline(self)
  self.buf:linestart()
  local t = ''
  for i = self.buf.cur, #self.buf.text do
    t = t .. self.buf.text[i]
  end
  t = t:gsub("^%$", ""):strip()
  self.buf:lineend()
  self.buf:input '\n'
  local cmd = t:split(1)
  if cmd[1] == 'cd' and #cmd == 2 then
    local r, e = sys.chdir(cmd[2])
    if not r then
      self.buf:input("Error\n")
    end
    self.buf:input '$ '
  else
    pipe(self, t, false, true)
  end
end

function proc.win(w)
  w = w:output("+win")
  if not w.win_shell then
    w.win_shell = true
    w:input("$ ")
  end
  w.newline = win_newline
end

--luacheck: pop

if PLATFORM ~= 'Windows' then
proc['|'] = function(w, prog)
  local data = w:data()
  if not data then return end

  local tmp = os.tmpname()
  local f = io.open(tmp, "wb")
  if not f then
    return
  end
  local s, e = data.buf:range()
  f:write(data.buf:gettext(s, e))
  f:close()
  data.buf:setsel(s, e + 1)
  data.buf:cut()
  pipe(w:data(), 'cat '..tmp..'|'..prog..' 2>&1', tmp)
end
end

return proc
