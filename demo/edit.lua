-- gfx.win(384, 384)
local W, H = screen:size()
local conf = {
  fg = 0,
  bg = 16,
  hl = { 0, 0, 128, 64 },
  status = { 0, 0, 0, 64 },
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
  local b = { text = {}, cur = { x = 1, y = 1 },
    line = 1, col = 1, fname = fname, hist = {},
    sel = { } }
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
  local info = string.format("%s%s %2d:%-2d",
    s.dirty and '*' or '', s.fname, s.cur.x, s.cur.y)
  screen:fill_rect(0, H - s.sph, W, H, conf.status)
  gfx.print(info, 0, H - s.sph, conf.fg)
end

function buff:cut()
  local s = self
  local x1, y1 = s.sel.x, s.sel.y
  local x2, y2 = s.sel.endx, s.sel.endy
  if not x1 or not x2 or y1 == y2 and x1 == x2 then return end
  if y1 > y2 then
    y1, y2 = y2, y1
    x1, x2 = x2, x1
  end

  local yy = y1

  for y=y1, y2 do
    if y ~= y1 and y ~= y2 then -- full line
      s.text[yy] = {}
    elseif y == y1 then
      for x=x1, y == y2 and x2-1 or #s.text[yy] do
        table.remove(s.text[yy], x1)
      end
    elseif y == y2 then
      local xx = y==y1 and x1 or 1
      for x = xx, x2-1 do
        table.remove(s.text[yy], xx)
      end
    end
    if #s.text[yy] == 0 then
      table.remove(s.text, yy)
    else
      yy = yy + 1
    end
  end
  s.cur.x, s.cur.y = x1, y1
  s.sel.x, s.sel.endx = false, false
end

function buff:hlight(nr, py)
  local s = self
  local x1, y1 = s.sel.x, s.sel.y
  local x2, y2 = s.sel.endx, s.sel.endy
  if not x1 or not x2 then return end
  if y1 == y2 and x1 == x2 then return end
  if y1 > y2 then
    y1, y2 = y2, y1
    x1, x2 = x2, x1
  end
  if nr < y1 or nr > y2 then return end
  if nr > y1 and nr < y2 then -- full line
    local len = #s.text[nr]
    screen:fill_rect(0, py, len*s.spw-1, py + s.sph - 1, conf.hl)
    return
  end
  if nr == y1 then
    if y2 ~= nr then x2 = #s.text[nr] + 1 end
    screen:fill_rect((x1-1)*s.spw, py, (x2-1)*s.spw, py + s.sph - 1, conf.hl)
    return
  end
  if nr == y2 then
    if y1 ~= nr then x1 = 1 end
    screen:fill_rect((x1-1)*s.spw, py, (x2-1)*s.spw, py + s.sph - 1, conf.hl)
    return
  end
end

function buff:show()
  local s = self
  screen:clear(conf.bg)
  local l, words
  local px, py = 0, 0
  for nr=s.line, s.line + s.lines - 1 do
    l = s.text[nr] or {}
    px = 0
    s:hlight(nr, py)
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
  s:history()
  for _, v in ipairs(c) do
    table.insert(s.text[s.cur.y], s.cur.x, v)
  end
  s.cur.x = s.cur.x + utf.len(t)
  s:scroll()
end

function buff:history(newln)
  local s = self
  local l = {}
  for _, v in ipairs(s.text[s.cur.y]) do
    table.insert(l, v)
  end
  table.insert(s.hist,
    { nr = s.cur.y, line = l, x = s.cur.x, newline = newln })
  if #s.hist > 1024 then
    table.remove(s.hist, 1)
  end
  s.dirty = true
end

function buff:undo()
  local s = self
  if #s.hist == 0 then return end
  local h = table.remove(s.hist, #s.hist)
  s.text[h.nr] = h.line
  if h.newline then
    table.remove(s.text, h.nr + 1)
  end
  s.cur.x = h.x
  s.cur.y = h.nr
  s.dirty = #s.hist ~= 0
end

function buff:select(on)
  local s = self
  if on == true then
    if not s.sel.start then
      s.sel.x, s.sel.y = s.cur.x, s.cur.y
    end
    s.sel.endx, s.sel.endy = s.cur.x, s.cur.y
    s.sel.start = true
    return
  elseif on == false then
    s.sel.start = false
    return
  end
  if s.sel.start then
    s.sel.endx, s.sel.endy = s.cur.x, s.cur.y
  end
end


function buff:getind(nr)
  local s = self
  local l = s.text[nr] or {}
  local ind = 0
  for i=1, #l do
    if l[i] == ' ' then ind = ind + 1 else break end
  end
  return ind
end

function buff:keyup(k)
  local s = self
  if k:find 'shift' then
    s:select(false)
  end
end

function buff:keydown(k)
  local s = self
  if k:find 'shift' then
    s:select(true)
  elseif k == 'up' then
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
    local ind, ind2 = 0, 0
    if s.cur.x > 1 then
      ind = s:getind(s.cur.y)
      ind2 = s:getind(s.cur.y+1)
      ind = ind > ind2 and ind or ind2
    end
    s:history(true)
    table.insert(s.text, s.cur.y + 1, {})
    for i=1,ind do
      table.insert(s.text[s.cur.y + 1], 1, ' ')
    end
    for k=s.cur.x, #l do
      table.insert(s.text[s.cur.y+1], table.remove(l, s.cur.x))
    end
    s.cur.y = s.cur.y + 1
    s.cur.x = ind + 1
  elseif k == 'backspace' then
    if s.cur.x > 1 then
      s:history()
      table.remove(s.text[s.cur.y], s.cur.x - 1)
      s.cur.x = s.cur.x - 1
    elseif s.cur.y > 1 then
      s:history()
      local l = table.remove(s.text, s.cur.y)
      s.cur.y = s.cur.y - 1
      s.cur.x = #s.text[s.cur.y] + 1
      s:history()
      for _, v in ipairs(l) do
        table.insert(s.text[s.cur.y], v)
      end
    end
  elseif k == 'tab' then
    s:input("  ")
  elseif k == 'f2' or (k == 's' and input.keydown'ctrl') then
    s:write()
  elseif (k == 'u' or k == 'z') and input.keydown 'ctrl' then
    s:undo()
  elseif k == 'x' and input.keydown 'ctrl' then
    s:cut()
  end
  s:scroll()
  s:select()
end

b = buff.new(FILE)

while true do
  local r, v = sys.input()
  if r == 'keydown' then
    b:keydown(v)
  elseif r == 'keyup' then
    b:keyup(v)
  elseif r == 'text' then
    b:input(v)
  end
  b:show()
  gfx.flip(1/20, true)
end
