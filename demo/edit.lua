--gfx.win(640, 480)
--local sfont = gfx.font('demo/iosevka.ttf',12)
local idle_mode
local inp_mode
local sfont = font
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

local function clone(t)
  local l = {}
  for _, v in ipairs(t) do
    table.insert(l, v)
  end
  return l
end

function glyph(t, col)
  col = col or conf.fg
  local key = string.format("%s-%s", t, col)
  if glyph_cache[key] then
    return glyph_cache[key]
  end
  glyph_cache[key] = sfont:text(t, col)
  return glyph_cache[key]
end

function buff.new(fname, x, y, w, h)
  local b = { text = { }, cur = { x = 1, y = 1 },
    line = 1, col = 1, fname = fname, hist = {},
    sel = { }, x = x or 0, y = y or 0, w = w or W, h = h or H }
  local f = fname and io.open(fname, "rb")
  if f then
    for l in f:lines() do
      table.insert(b.text, utf.chars(l))
    end
    f:close()
  end
  b.spw, b.sph = sfont:size(" ")
  b.lines = math.floor(b.h / b.sph) - 1 -- status line
  b.columns = math.floor(b.w / b.spw)
  setmetatable(b, buff)
  return b
end

function buff:write()
  local s = self
  if type(s.fname) ~= 'string' then
    return
  end
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
  local s = self
  if math.floor(sys.time()*4) % 2 == 1 then
    return
  end
  local px, py = (s.cur.x - s.col)*s.spw, (s.cur.y - s.line)*s.sph
  for y=py, py + s.sph-1 do
    for x=px, px + s.spw-1 do
      local r, g, b = screen:val(s.x + x, s.y + y)
      r = bit.bxor(r, 255)
      g = bit.bxor(g, 255)
      b = bit.bxor(b, 255)
      screen:val(s.x + x, s.y + y, {r, g, b, 255})
    end
  end
end

function buff:status()
  local s = self
  local info = string.format("%s%s %2d:%-2d",
    s.dirty and '*' or '', s.fname, s.cur.x, s.cur.y)
  screen:fill_rect(0, H - s.sph, W, H, conf.status)
  sfont:text(info, conf.fg):blend(screen, 0, H - s.sph)
end

function buff:selected()
  local s = self
  local is = s.sel.x and s.sel.endx and
    (s.sel.x ~= s.sel.endx or s.sel.y ~= s.sel.endy)
  if not is then
    return false
  end
  local x1, x2 = s.sel.x, s.sel.endx
  if x1 > x2 then x1, x2 = s.sel.endx, s.sel.x end
  local t = ''
  for x=x1, x2-1 do
    t = t .. s.text[s.sel.y][x]
  end
  return t
end

function buff:unselect()
  local s = self
  s.sel.x, s.sel.endx, s.sel.start = false, false, false
end

function buff:paste()
  local s = self
  for _, c in ipairs(s.clipboard or {}) do
    s:input(table.concat(c, ''))
    s:newline()
  end
end

function buff:cut(copy)
  local s = self
  local x1, y1 = s.sel.x, s.sel.y
  local x2, y2 = s.sel.endx, s.sel.endy

  s.clipboard = {}

  if not x1 or not x2 or y1 == y2 and x1 == x2 then return end
  if y1 > y2 then
    y1, y2 = y2, y1
    x1, x2 = x2, x1
  end
  if y1 == y2 and x1 > x2 then x1, x2 = x2, x1 end
  if not copy then
    s:history('cut', x1, y1, x2, y2)
  end
  local yy = y1

  for y=y1, y2 do
    if y ~= y1 and y ~= y2 then -- full line
      table.insert(s.clipboard, s.text[yy])
      if not copy then
        s.text[yy] = {}
      end
    elseif y == y1 then
      local crow = {}
      table.insert(s.clipboard, crow)
      for x=x1, y == y2 and x2-1 or #s.text[yy] do
        table.insert(crow, s.text[yy][x])
      end
      if not copy then
        for x=x1, y == y2 and x2-1 or #s.text[yy] do
          table.remove(s.text[yy], x1)
        end
      end
    elseif y == y2 then
      local crow = {}
      table.insert(s.clipboard, crow)
      local xx = y == y1 and x1 or 1
      for x = xx, x2-1 do
        table.insert(crow, s.text[yy][x])
      end
      if not copy then
        for x = xx, x2-1 do
          table.remove(s.text[yy], xx)
        end
      end
    end
    if #s.text[yy] == 0 and not copy then
      table.remove(s.text, yy)
    else
      yy = yy + 1
    end
  end
  if not copy then
    s.cur.x, s.cur.y = x1, y1
    s:unselect()
  end
end

function buff:hlight(nr, py)
  local s = self
  local x1, y1 = s.sel.x, s.sel.y
  local x2, y2 = s.sel.endx, s.sel.endy
  if not x1 or not x2 then return end
  if not s.text[nr] then return end
  if y1 == y2 and x1 == x2 then return end
  if y1 > y2 then
    y1, y2 = y2, y1
    x1, x2 = x2, x1
  end
  if nr < y1 or nr > y2 then return end
  if nr > y1 and nr < y2 then -- full line
    local len = #s.text[nr]
    screen:offset(-(s.col-1)*s.spw, 0)
    screen:fill_rect(s.x, py, s.x + len*s.spw-1,
      py + s.sph - 1, conf.hl)
    screen:nooffset()
    return
  end
  if nr == y1 then
    if y2 ~= nr then x2 = #s.text[nr] + 1 end
    screen:offset(-(s.col-1)*s.spw, 0)
    screen:fill_rect(s.x + (x1-1)*s.spw, py,
      s.x + (x2-1)*s.spw, py + s.sph - 1, conf.hl)
    screen:nooffset()
    return
  end
  if nr == y2 then
    if y1 ~= nr then x1 = 1 end
    screen:offset(-(s.col-1)*s.spw, 0)
    screen:fill_rect(s.x + (x1-1)*s.spw, py,
      s.x + (x2-1)*s.spw, py + s.sph - 1, conf.hl)
    screen:nooffset()
    return
  end
end

function buff:show()
  local s = self
  screen:clear(s.x, s.y, s.w, s.h, conf.bg)
  screen:clip(s.x, s.y, s.x + s.w, s.y + s.h)
  local l, words
  local px, py = s.x, s.y
  for nr=s.line, s.line + s.lines - 1 do
    l = s.text[nr] or {}
    px = 0
    s:hlight(nr, py)
    for i=s.col,#l do
      if px > W then
        break
      end
      local g = glyph(l[i])
      if not g then g = glyph("?") end
      local w, _ = g:size()
      g:blend(screen, px, py)
      px = px + w
    end
    py = py + s.sph
  end
  screen:noclip()
  if s.status then
    s:status()
  end
  s:cursor()
end

function buff:scroll()
  local s = self
  if #s.text == 0 then s.text[1] = {} end
  if s.cur.x < 1 then s.cur.x = 1 end
  if s.cur.y < 1 then s.cur.y = 1 end
  if s.cur.y > #s.text then
    s.cur.y = #s.text
    if #s.text[s.cur.y] ~= 0 then
      s.cur.y = s.cur.y + 1
      s.cur.x = 1
      s.text[s.cur.y] = {}
    end
  end
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

function buff:history(op, a, b, c, d)
  local s = self
  local h = { op = op, x = s.cur.x, y = s.cur.y }
  if op == 'cut' then
    h.op = 'cut'
    h.nr = b
    h.endn = d
    h.edita = a > 1
    h.editb = c <= #s.text[b]
    for y=b,d do
      table.insert(h, clone(s.text[y]))
    end
  else
    h.nr = s.cur.y
    h.line = clone(s.text[s.cur.y])
  end
  table.insert(s.hist, h)
  if #s.hist > 1024 then
    table.remove(s.hist, 1)
  end
  s.dirty = true
end

function buff:undo()
  local s = self
  if #s.hist == 0 then return end
  local h = table.remove(s.hist, #s.hist)
  if h.op == 'cut' then
    for k, l in ipairs(h) do
      if k == 1 and h.edita then table.remove(s.text, h.nr)
      elseif k == #h and h.editb then table.remove(s.text, h.nr + k - 1) end
      table.insert(s.text, h.nr + k - 1, l)
    end
  else
    s.text[h.nr] = h.line
    if h.op == 'newline' then
      table.remove(s.text, h.nr + 1)
    end
  end
  s.cur.x = h.x
  s.cur.y = h.y
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

function buff:delete()
-- todo
end

function buff:backspace()
  local s = self
  s:unselect()
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
end

function buff:newline()
  local s = self
  local l = s.text[s.cur.y]
  local ind, ind2 = 0, 0
  if s.cur.x > 1 then
    ind = s:getind(s.cur.y)
    ind2 = s:getind(s.cur.y+1)
    ind = ind > ind2 and ind or ind2
  end
  s:history('newline')
  table.insert(s.text, s.cur.y + 1, {})
  for i=1,ind do
    table.insert(s.text[s.cur.y + 1], 1, ' ')
  end
  for k=s.cur.x, #l do
    table.insert(s.text[s.cur.y+1], table.remove(l, s.cur.x))
  end
  s.cur.y = s.cur.y + 1
  s.cur.x = ind + 1
  s:unselect()
end

function buff:jump(nr)
  local s = self
  s.cur.y = nr
  s:unselect()
  s:scroll()
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
  elseif k == 'pagedown' or k == 'keypad 3' then
    s.cur.y = s.cur.y + s.lines
    s:scroll()
    s.line = s.cur.y
  elseif k == 'pageup' or k == 'keypad 9' then
    s.cur.y = s.cur.y - s.lines
    s:scroll()
    s.line = s.cur.y
  elseif k == 'return' then
    s:newline()
  elseif k == 'backspace' then
    s:backspace()
  elseif k == 'tab' then
    s:input("  ")
  elseif k == 'f2' or (k == 's' and input.keydown'ctrl') then
    s:write()
  elseif k == 'f5' then
    s:write()
    mixer.init()
    local f, e = sys.exec(FILE)
    if not f then
      idle_mode = sys.go(function() error(e) end)
    else
      idle_mode = f
    end
  elseif (k == 'u' or k == 'z') and input.keydown 'ctrl' then
    s:undo()
  elseif k == 'x' and input.keydown 'ctrl' or k == 'delete' then
    if k == 'delete' and not s:selected() then
      s:delete()
    else
      s:cut()
    end
  elseif k == 'c' and input.keydown 'ctrl' then
    s:cut(true)
  elseif k == 'v' and input.keydown 'ctrl' then
    s:paste()
  elseif (k == 'f' and input.keydown 'ctrl') or k == 'f7' then
    inp_mode = not inp_mode
    if inp_mode then
      local t =  s:selected()
      if t then
        inp_mode = false
        s:search(t)
      else
        inp_mode = 'search'
      end
    end
  elseif k == 'l' and input.keydown 'ctrl' then
    inp_mode = not inp_mode
    if inp_mode then
      inp_mode = 'goto'
    end
  end
  s:scroll()
  s:select()
end

function buff:search(t)
  local s = self
  for y = s.cur.y, #s.text do
    local l = table.concat(s.text[y], '')
    local start = 0
    if y == s.cur.y then
      local chars = s.text[y]
      for i=1,s.cur.x+1 do
        start = start + (chars[i] or ' '):len()
      end
    end
    if l:find(t, start, true) then
      local b, e = l:find(t, start, true)
      local pos = 1
      for i=1,#s.text[y] do
        if pos == b then
          s.cur.x = pos
        end
        if pos == e then
          s.sel.endx = pos + 1
          break
        end
        pos = pos + s.text[y][i]:len()
      end
      s.cur.y = y
      s.sel.x = s.cur.x
      s.sel.y = y
      s.sel.endy = y
      s:scroll()
      return true
    end
  end
  return false
end

local b = buff.new(FILE)
local inp = buff.new(false, 0, H - b.sph, W, b.sph)
inp.status = false
inp.lines = 1

function inp:newline()
  local s = self
  if inp_mode == 'search' then
    b:search(table.concat(s.text[1] or {}, ''))
  elseif inp_mode == 'goto' then
    b:jump(tonumber(table.concat(s.text[1] or {}, '')) or 1)
  end
  s.text = {}
  inp_mode = false
end

function get_buff()
  return inp_mode and inp or b
end
mixer.stop()

while true do
  while idle_mode do
    if input.keypress("c") and input.keydown("ctrl") then
      sys.stop(idle_mode)
      mixer.stop()
      screen:nooffset()
      screen:noclip()
      idle_mode = false
      break
    end
    coroutine.yield()
  end
  local r, v = sys.input()
  if r == 'keydown' then
    get_buff():keydown(v)
  elseif r == 'keyup' then
    get_buff():keyup(v)
  elseif r == 'text' then
    get_buff():unselect()
    get_buff():input(v)
  end
  if not gfx.framedrop() then
    get_buff():show()
  end
  gfx.flip(1/20, true)
end
