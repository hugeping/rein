local editor = {}
editor.__index = editor
function editor.new()
  local ed = { cur = {x = 1, y = 1},
    col = 1, line = 1, lines = {}, 
    sel = {}, hl = { 0, 0, 0, 32 }, hist = {},
  }
  setmetatable(ed, editor)
  return ed
end

function editor:set(text)
  self.lines = {}
  for l in text:lines() do
    table.insert(self.lines, utf.chars(l))
  end
end

function editor:get()
  local text = ''
  for _, l in ipairs(self.lines) do
    text = text .. table.concat(l) .. '\n'
  end
  return text
end

function editor:size(w, h)
  local s = self
  if not w then
    return s.width, s.height
  end
  s.width, s.height = w, h
end

function editor:move(x, y)
  local s = self
  if x then s.cur.x = x end
  if y then s.cur.y = y end
  if #s.lines == 0 then
    s.cur.x, s.cur.y = 1, 1
    s.lines[1] = {}
    return
  end
  if s.cur.x < 1 then s.cur.x = 1 end
  if s.cur.y < 1 then s.cur.y = 1 end
  if s.cur.y > #s.lines then
    s.cur.y = #s.lines
    if #s.lines[s.cur.y] ~= 0 then
      s.cur.y = s.cur.y + 1
      s.cur.x = 1
      s.lines[s.cur.y] = {}
    end
  end
  if s.cur.x > #s.lines[s.cur.y] then s.cur.x = #s.lines[s.cur.y] + 1 end
  local columns, lines = self:size()
  if s.cur.y >= s.line and s.cur.y <= s.line + lines - 1
    and s.cur.x >= s.col and s.cur.x < columns then
    return
  end
  if s.cur.x < s.col then
    s.col = s.cur.x
  elseif s.cur.x > s.col + columns - 1 then
    s.col = s.cur.x - columns + 1
  end
  if s.cur.y < s.line then
    s.line = s.cur.y
  elseif s.cur.y > s.line + lines - 1 then
    s.line = s.cur.y - lines + 1
  end
end

function editor:input(t)
  local s = self
  local c = utf.chars(t)
  s:history()
  for _, v in ipairs(c) do
    table.insert(s.lines[s.cur.y], s.cur.x, v)
    s.cur.x = s.cur.x + 1
  end
  s:move()
end


local function clone(t)
  local l = {}
  for _, v in ipairs(t) do
    table.insert(l, v)
  end
  return l
end

function editor:history(op, x1, y1, x2, y2)
  local s = self
  y1 = y1 or s.cur.y
  y2 = y2 or s.cur.y
  local h = { op = op, x = s.cur.x, y = s.cur.y,
    nr = y1, rem = 0 }
  if op == 'cut' then
    if y1 == y2 then
      h.rem = x2 - x1 < #s.lines[y1] and 1 or 0
    else
      h.rem = x1 > 1 and 1 or 0
      if x2 < #s.lines[y2] then
        h.rem = h.rem + 1
      end
      -- h.rem = h.rem + y2 - y1 - 1
    end
  end
  for i = 1, y2 - y1 + 1 do
    table.insert(h, clone(s.lines[y1 + i - 1]))
  end
  table.insert(s.hist, h)
  if #s.hist > 1024 then
    table.remove(s.hist, 1)
  end
end

function editor:undo()
  local s = self
  if #s.hist == 0 then return end
  local h = table.remove(s.hist, #s.hist)
  if h.op == 'cut' then
    for i=1, h.rem do
      table.remove(s.lines, h.nr)
    end
    for k, l in ipairs(h) do
      table.insert(s.lines, h.nr + k - 1, l)
    end
  else
    for k, l in ipairs(h) do
      s.lines[h.nr + k - 1] = l
    end
    if h.op == 'newline' then
      table.remove(s.lines, h.nr + 1)
    end
  end
  s.cur.x = h.x
  s.cur.y = h.y
end

function editor:selection()
  local s = self
  local x1, y1 = s.sel.x, s.sel.y
  local x2, y2 = s.sel.endx, s.sel.endy

  if not x2 or (y1 == y2 and x1 == x2) then
    return
  end
  if y1 > y2 then
    y1, y2 = y2, y1
    x1, x2 = x2, x1
  end
  if y1 == y2 and x1 > x2 then x1, x2 = x2, x1 end
  return x1, y1, x2, y2
end

function editor:insel(x, nr)
  local s = self
  local x1, y1, x2, y2 = s:selection()
  if not x1 or not s.lines[nr] then return end
  if nr < y1 or nr > y2 then return end -- fast path
  if nr > y1 and nr < y2 then -- full line
    return true
  end
  if nr == y1 then
    if x < x1 then return end
    if y2 == nr and x >= x2 then return end
    return true
  end
  if nr == y2 then
    if x >= x2 then return end
    if y2 == nr and x > x2 then return end
    return true
  end
end

function editor:unselect()
  local s = self
  s.sel.x, s.sel.endx, s.sel.start = false, false, false
end

function editor:select(on)
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

function editor:cut(copy)
  local s = self
  local x1, y1, x2, y2 = s:selection()

  local clipboard = ''
  if not x1 then return end
  local yy = y1
  if not copy then
    s:history('cut', x1, y1, x2, y2)
  end
  for y=y1, y2 do
    local nl = {}
    if y ~= y1 and y ~= y2 then -- full line
      clipboard = clipboard .. table.concat(s.lines[yy])..'\n'
    else
      for x=1, #s.lines[yy] do
        if s:insel(x, y) then
          clipboard = clipboard .. s.lines[yy][x]
          if x == #s.lines[yy] then
            clipboard = clipboard .. '\n'
          end
        else
          table.insert(nl, s.lines[yy][x])
        end
      end
    end
    if #nl == 0 and not copy then
      table.remove(s.lines, yy)
    else
      s.lines[yy] = copy and s.lines[yy] or nl
      yy = yy + 1
    end
  end
  if not copy then
    s.cur.x, s.cur.y = x1, y1
    s:unselect()
  end
  sys.clipboard(clipboard)
  s.clipboard = clipboard
  return clipboard
end


function editor:delete()
  local s = self
  if s.cur.x <= #s.lines[s.cur.y] then
    s:history()
    table.remove(s.lines[s.cur.y], s.cur.x)
  elseif s.cur.x > #s.lines[s.cur.y] and s.lines[s.cur.y+1] then
    s:history()
    s.cur.y = s.cur.y + 1
    s:history()
    local l = table.remove(s.lines, s.cur.y)
    s.cur.y = s.cur.y - 1
    for _, v in ipairs(l) do
      table.insert(s.lines[s.cur.y], v)
    end
  end
end

function editor:newline()
  local s = self
  local l = s.lines[s.cur.y]
  s:history('newline')
  table.insert(s.lines, s.cur.y + 1, {})
  for k=s.cur.x, #l do
    table.insert(s.lines[s.cur.y+1], table.remove(l, s.cur.x))
  end
  s.cur.y = s.cur.y + 1
  s.cur.x = 1
end

function editor:backspace()
  local s = self
  if s.cur.x > 1 then
    s:history()
    table.remove(s.lines[s.cur.y], s.cur.x - 1)
    s.cur.x = s.cur.x - 1
  elseif s.cur.y > 1 then
    s:history()
    local l = table.remove(s.lines, s.cur.y)
    s.cur.y = s.cur.y - 1
    s.cur.x = #s.lines[s.cur.y] + 1
    s:history()
    for _, v in ipairs(l) do
      table.insert(s.lines[s.cur.y], v)
    end
  end
end

function editor:paste()
  local s = self
  local text = sys.clipboard() or s.clipboard or ''
  for l in text:lines() do
    s:input(l)
    s:newline()
  end
end

function editor:toend()
  self.cur.x = #self.lines[self.cur.y] + 1
end

function editor:coord(x, y)
  return x - self.col + 1, y - self.line + 1
end

function editor:cursor()
  return self.cur.x, self.cur.y
end

function editor:cutline()
  self:history('cut', 1, self.cur.y, #self.lines[self.cur.y] + 1, self.cur.y)
  table.remove(self.lines, self.cur.y)
end

function editor:visible_lines()
  local columns, lines = self:size()
  local nr = 0
  return function()
    if nr >= lines then
      return
    end
    nr = nr + 1
    local l = self.lines[nr + self.line - 1]
    if not l then
      return
    end
    local n = columns + self.col - 1
    return nr, self.col, n > #l and #l or n
  end
end

return editor
