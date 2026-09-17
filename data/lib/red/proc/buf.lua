-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local sub_delims = {
  ["/"] = true,
  [":"] = true,
}

local sub_esc = {
  ["\\t"] = "\t",
  ["\\n"] = "\n",
  ["\\r"] = "\r",
}

local function sub(w, text, glob)
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

local function gsub(w, text)
  return sub(w, text, true)
end

local function find(w, pat)
  return sub(w, pat)
end

local function gfind(w, pat)
  return gsub(w, pat)
end

local function codepoint(w)
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

local function line(w)
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

local function clear(w)
  w = w:data()
  if not w then return end
  w.buf:setsel(1, #w.buf.text + 1)
  w.buf:cut()
  w:visible()
  return true
end

return {
  gsub = gsub,
  sub = sub,
  find = find,
  gfind = gfind,
  Codepoint = codepoint,
  Line = line,
  Clear = clear,
}
