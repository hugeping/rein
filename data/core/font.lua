local font = {
}
local fn = {
}

fn.__index = fn

local function parse_line(l)
  local r = { }
  for i=1,l:len() do
    local c = string.byte(l, i)
    if c == string.byte '-' or c == string.byte ' ' then
      table.insert(r, 0)
    else
      table.insert(r, 255)
    end
  end
  return r
end

function font.new(fname)
  local fnt = { w = 0, h = 0 }
  local f, e = io.open(fname, "rb")
  if not f then
    return false, e
  end
  local nr = 1
  local cp = false
  for l in f:lines() do
    l = l:gsub("\r", "")
    if cp then
      if l:find("^[ \t]*$") then
        cp = false
      else
        local r = parse_line(l)
        if fnt[cp].w < #r then
          fnt[cp].w = #r
        end
        fnt[cp].h = fnt[cp].h + 1
        table.insert(fnt[cp], r)
      end
    elseif l:find("^[ \t]*0x[0-9a-fA-F]+[ \t]*$") then
      cp = l:gsub("^[ \t]*", ""):gsub("[ \t]*$", "")
      cp = tonumber(cp)
      if not cp then
        return false, "Error in format. Line:"..tostring(nr)
      end
      fnt[cp] = { w = 0, h = 0 }
    end
    nr = nr + 1
  end
  for k, v in pairs(fnt) do
    if type(k) == 'number' then
      if v.w > fnt.w then
        fnt.w = v.w
      end
      if v.h > fnt.h then
        fnt.h = v.h
      end
      v.spr = gfx.new(v.w, v.h)
    end
  end
  setmetatable(fnt, fn)
  return fnt
end

function fn:size(t)
  local w, h = 0, 0
  while t and t ~= '' do
    local c, n = sys.utf_sym(t)
    if not n or n == 0 then
      break
    end
    local cp = sys.utf_codepoint(c)
    local v = self[cp]
    if v then
      w = w + v.w
      if v.h > h then
        h = v.h
      end
    end
    t = t:sub(n + 1)
  end
  return w, h
end

function fn:glyph(cp, color)
  color = {gfx.pal(color)}
  local col = { color[1], color[2], color[3] }
  local v = self[cp]
  if not v then return end
  local key = string.format("%02x%02x%02x",
    color[1], color[2], color[3])
  if v.key == key then -- cached!
    return v.spr
  end
  v.spr:clear { 0, 0, 0, 0 }
  for y=1,v.h do
    for x=1,v.w do
      col[4] = v[y][x] or 0
      v.spr:pixel(x - 1, y - 1, col)
    end
  end
  v.key = key
  return v.spr
end

function fn:text(t, color)
  local w, h = self:size(t)
  local spr = gfx.new(w, h)
  local x = 0
  while t and t ~= '' do
    local c, n = sys.utf_sym(t)
    if not n or n == 0 then
      break
    end
    local cp = sys.utf_codepoint(c)
    local v = self[cp]
    if v then
      self:glyph(cp, color):copy(spr, x, 0)
      x = x + v.w
    end
    t = t:sub(n + 1)
  end
  return spr
end

return font
