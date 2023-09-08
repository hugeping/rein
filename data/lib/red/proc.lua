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

local function text_match(w, fn, ...)
  local s, e = w.buf.cur, #w.buf.text
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

local function text_replace(w, fn, ...)
  if not w.buf:issel() then
    return text_match(w, function(text, pat)
      return text:findln(pat)
    end, ...)
  end
  local s, e = w.buf:range()
  local text = w.buf:gettext(s, e)
  text = fn(text, ...)
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
            coroutine.yield()
          end
        end
        f:close()
      end
    end
  end
end

function proc.grep(w, rex)
  w = w:output()
  w:run(function()
    grep(sys.dirname(w.frame:getfilename()), rex, w)
  end)
end

--luacheck: push
--luacheck: ignore 432
function proc.gsub(w, text)
  w = w:winmenu()
  if not w then return end
  text = text:strip()
  local u = utf.chars(text)
  local delim = u[1]
  local a = text:split(delim)
  table.remove(a, 1)
  if not a[2] then
    text_match(w, function(text, pat)
      return text:findln(pat)
    end, a[1])
    return
  end
  text_replace(w, function(text, a, b)
    local t = ''
    for l in text:lines(true) do
      l = l:gsub(a, b)
      t = t .. l
    end
    return t
  end, a[1], a[2])
end
function proc.find(w, pat)
  w = w:winmenu()
  if not w then return end
  text_match(w, function(text, pat)
    return text:findln(pat)
  end, pat)
end

function proc.select(w, pat)
  w = w:winmenu()
  if not w then return end
  text_match(w, function(text, pat)
    if text == '' then return end
    return text:find(pat)
  end, pat)
end

proc['!'] = function(w, pat)
  w = w:output()
  w:run(function()
    local f = io.popen(pat, "r")
    if not f then return end
    for l in f:lines() do
      w:input(l ..'\n')
      coroutine.yield()
    end
    f:close()
  end)
end

--luacheck: pop

return proc
