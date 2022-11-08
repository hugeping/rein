-- gfx.win(384, 384)
local W, H = screen:size()
local conf = {
  fg = 0,
  bg = 16,
}

local FILE = ARGS[2] or 'main.lua'

local buff = {
}
buff.__index = buff

local glyph_cache = {}

function glyph(t, col)
  col = col or conf.fg
  local key = string.format("%s-%s", t, col)
  if glyph_cache[key] then
    return glyph_cache[key]
  end
  glyph_cache[key] = font:text(t, col)
  return glyph_cache[key]
end

function buff.new(fname)
  local b = { text = {}, cur = { x = 1, y = 1 }, line = 1, col = 1, fname = fname }
  local f = io.open(fname, "rb")
  if f then
    for l in f:lines() do
      table.insert(b.text, utf.chars(l))
    end
    f:close()
  end
  b.spw, b.sph = font:size(" ")
  b.lines = math.floor(H / b.sph) - 1 -- status line
  b.columns = math.floor(W / b.spw)
  setmetatable(b, buff)
  return b
end

function buff:write()
  local s = self
  local f = io.open(s.fname, "wb")
  if not f then
    return
  end
  for _, l in ipairs(s.text) do
    l = table.concat(l, ''):gsub("[ \t]+$", "") -- strip
    f:write(l.."\n")
  end
  f:close()
  s.dirty = false
  print(string.format("%s written", s.fname))
end

function buff:cursor()
  if math.floor(sys.time()*4) % 2 == 1 then
    return
  end
  local s = self
  local px, py = (s.cur.x - s.col), (s.cur.y - s.line)
  py = py * s.sph  
  px = px * s.spw
  for y=py, py + s.sph-1 do
    for x=px, px + s.spw-1 do
      local r, g, b = screen:val(x, y)
      r = bit.bxor(r, 255)
      g = bit.bxor(g, 255)
      b = bit.bxor(b, 255)
      screen:val(x, y, {r, g, b, 255})
    end
  end
end

function buff:status()
  local s = self
  local info = string.format("%s %2d:%-2d", s.fname, s.cur.x, s.cur.y)
  screen:fill_rect(0, H - s.sph, W, H, { 0, 0, 0, 64 })
  gfx.print(info, 0, H - s.sph, 0)
end

function buff:show()
  local s = self
  screen:clear(conf.bg)
  local l, words
  local px, py = 0, 0
  for nr=s.line, s.line + s.lines - 1 do
    l = s.text[nr] or {}
    px = 0
    for i=b.col,#l do
      if px > W then
        break
      end
      local g = glyph(l[i])
      local w, _ = g:size()
      g:blend(screen, px, py)
      px = px + w
    end
    py = py + s.sph
  end
  s:status()
  s:cursor()
end

function buff:scroll()
  local s = self
  if s.cur.x < 1 then s.cur.x = 1 end
  if s.cur.y < 1 then s.cur.y = 1 end
  if s.cur.y > #s.text then s.cur.y = #s.text end
  if s.cur.x > #s.text[s.cur.y] then s.cur.x = #s.text[s.cur.y] + 1 end
  if s.cur.y >= s.line and s.cur.y <= s.line + s.lines - 1
    and s.cur.x >= s.col and s.cur.x < s.columns then
    return
  end
  if s.cur.x < s.col then
    s.col = s.cur.x
  elseif s.cur.x > s.col + s.columns - 1 then
    s.col = s.cur.x - s.columns + 1
  end
  if s.cur.y < s.line then
    s.line = s.cur.y
  elseif s.cur.y > s.line + s.lines - 1 then
    s.line = s.cur.y - s.lines + 1
  end
end

function buff:input(t)
  local s = self
  local c = utf.chars(t)
  for _, v in ipairs(c) do
    table.insert(s.text[s.cur.y], s.cur.x, v)
  end
  s.cur.x = s.cur.x + utf.len(t)
  s:scroll()
end

function buff:keydown(k)
  local s = self
  if k == 'up' then
    s.cur.y = s.cur.y - 1
  elseif k == 'down' then
    s.cur.y = s.cur.y + 1
  elseif k == 'right' then
    s.cur.x = s.cur.x + 1
  elseif k == 'left' then
    s.cur.x = s.cur.x - 1
  elseif k == 'home' or k == 'keypad 7' then
    s.cur.x = 1
  elseif k == 'end' or k == 'keypad 1' then
    s.cur.x = #s.text[s.cur.y] + 1
  elseif k == 'page down' or k == 'keypad 3' then
    s.cur.y = s.cur.y + s.lines
    s:scroll()
    s.line = s.cur.y
  elseif k == 'page up' or k == 'keypad 9' then
    s.cur.y = s.cur.y - s.lines
    s:scroll()
    s.line = s.cur.y
  elseif k == 'return' then
    local l = s.text[s.cur.y]
    table.insert(s.text, s.cur.y + 1, {})
    for k=s.cur.x, #l do
      table.insert(s.text[s.cur.y+1], table.remove(l, s.cur.x))
    end
    s.cur.y = s.cur.y + 1
    s.cur.x = 1
  elseif k == 'backspace' then
    if s.cur.x > 1 then
      table.remove(s.text[s.cur.y], s.cur.x - 1)
      s.cur.x = s.cur.x - 1
    elseif s.cur.y > 1 then
      local l = table.remove(s.text, s.cur.y)
      s.cur.y = s.cur.y - 1
      s.cur.x = #s.text[s.cur.y] + 1
      for _, v in ipairs(l) do
        table.insert(s.text[s.cur.y], v)
      end
    end
  elseif k == 'tab' then
    s:input("  ")
  elseif k == 'f2' or (k == 's' and input.keydown'ctrl') then
    s:write()
  end
  s:scroll()
end

b = buff.new(FILE)

while true do
  local r, v = sys.input()
  if r == 'keydown' then
    b:keydown(v)
  elseif r == 'text' then
    b:input(v)
  end
  b:show()
  gfx.flip(1/20, true)
end
