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
  if not w.buf:issel() or not b then
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

local function pipe(w, prog, tmp)
  if tmp then prog = 'cat '..tmp.. ' | '.. prog end
  if PLATFORM ~= 'Windows' then
    prog = prog .. ' 2>&1'
  end
  local f = io.popen(prog, "r")
  if not f then return end
  local p = w:run(function()
--    w:tail()
    local num = 1
    local cur = w:cur()
    w:history 'start'
    for l in f:lines() do
      w.buf:input(l ..'\n')
      num = num + 1
      if num % 100 == 0 then
        coroutine.yield()
      end
    end
    f:close()
    w:history 'end'
--    w.buf:setsel(cur, w:cur())
    w:cur(cur)
    if tmp then
      os.remove(tmp)
    end
  end)
  p.kill = function()
    if f then
      f:close()
      f = nil
      if tmp then
        os.remove(tmp)
      end
    end
  end
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
