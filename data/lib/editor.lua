local editor = {}
editor.__index = editor
function editor.new()
  local ed = { cur = {x = 1, y = 1},
    col = 1, line = 1, lines = {},
    sel = { mode = false }, hl = { 0, 0, 0, 32 }, hist = {},
    insert_mode = false,
  }
  setmetatable(ed, editor)
  return ed
end

function editor:set(text)
  self.lines = {}
  self:unselect()
  for l in text:lines() do
    table.insert(self.lines, utf.chars(l))
  end
  self:move(1, 1)
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

function editor:left()
  local s = self
  local x, y = s:cursor()
  if x > 1 or y == 1 then return s:move(x - 1) end
  y = y - 1
  x = #s.lines[y]
  return s:move(x + 1, y)
end

function editor:right()
  local s = self
  local x, y = s:cursor()
  if x <= #s.lines[y] or y > #s.lines then return s:move(x + 1) end
  return s:move(1, y + 1)
end

function editor:move(x, y)
  local s = self
  if x then s.cur.x = x end
  if y then s.cur.y = y end
  if #s.lines == 0 then
    s.cur.x, s.cur.y = 1, 1
    s.lines[1] = {}
    s.line = 1
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

function editor:input(t, replace)
  local s = self
  local c = utf.chars(t)
  if replace == nil then
    if s:insel(s:cursor()) then
      replace = true
    else
      s:unselect()
    end
  end
  if replace then
    s:history('start')
    s:cut(false, false)
  else
    s:unselect()
  end
  s:history()
  s.lines[s.cur.y] = s.lines[s.cur.y] or {}
  for _, v in ipairs(c) do
    if s:insmode() then
      s.lines[s.cur.y][s.cur.x] = v
    else
      table.insert(s.lines[s.cur.y], s.cur.x, v)
    end
    s.cur.x = s.cur.x + 1
  end
  if replace then
    s:history('end')
  end
  s:move()
end


local function clone(t)
  local l = {}
  for _, v in ipairs(t or {}) do
    table.insert(l, v)
  end
  return l
end

function editor:history(op, x1, y1, x2, y2)
  local s = self
  y1 = y1 or s.cur.y
  y2 = y2 or s.cur.y
  s.dirty = true
  local h = { op = op, x = s.cur.x, y = s.cur.y,
    nr = y1, rem = 0 }
  if op == 'cut' then
    if s:selmode() then
      h.rem = y2 - y1 + 1
    elseif y1 == y2 then
      h.rem = 1 --x2 - x1 < #s.lines[y1] and 1 or 0
    else
      h.rem = x1 > 1 and 1 or 0
--      if x2 < #s.lines[y2] then
      if x2 > 1 or #s.lines[y2] > 0 then
        h.rem = h.rem + 1
      end
--      end
      -- h.rem = h.rem + y2 - y1 - 1
    end
  end
  for i = 1, y2 - y1 + 1 do
    table.insert(h, clone(s.lines[y1 + i - 1]))
  end
--  if #h > 1 and #h[#h] == 0 then table.remove(h, #h) end
  table.insert(s.hist, h)
  if #s.hist > 1024 then
    table.remove(s.hist, 1)
  end
end

function editor:undo()
  local s = self
  if #s.hist == 0 then return end
  local h
  local sect = 0
  while true do
    h = table.remove(s.hist, #s.hist)
    if h.op == 'cut' then
      for i=1, h.rem do
        table.remove(s.lines, h.nr)
      end
      for k, l in ipairs(h) do
        table.insert(s.lines, h.nr + k - 1, l)
      end
    elseif h.op == 'end' then
      sect = sect + 1
    elseif h.op == 'start' then
      sect = sect - 1
    else
      for k, l in ipairs(h) do
        s.lines[h.nr + k - 1] = l
      end
      if h.op == 'newline' then
        table.remove(s.lines, h.nr + 1)
      end
    end
    if sect <= 0 then break end
  end
  s:move(h.x, h.y)
  s.dirty = #s.hist ~= 0
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
    if not s:selmode() then
      x1, x2 = x2, x1
    end
  end
  if (y1 == y2 or s:selmode()) and x1 > x2 then x1, x2 = x2, x1 end
  return x1, y1, x2, y2
end

function editor:selected()
  local x1, y1, x2, y2 = self:selection()
  if not x1 then return end
  local txt = ''
  for y=y1, y2 do
    local l = self.lines[y]
    for x=1, #l do
      if self:insel(x, y) then
        txt = txt .. l[x]
      end
    end
    if y ~= y2 then
      txt = txt .. '\n'
    end
  end
  return txt
end

function editor:insel(x, nr)
  local s = self
  local x1, y1, x2, y2 = s:selection()
  if not x1 then return end
  if s:selmode() then
    return nr >= y1 and nr <= y2 and x >= x1 and x <= x2
  end
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
    if y1 == nr and x < x1 then return end
    return true
  end
end

function editor:unselect()
  local s = self
  s.sel.x, s.sel.endx, s.sel.start = false, false, false
end

function editor:selmode(mode)
  local old = self.sel.mode
  if mode ~= nil then
    self.sel.mode = mode
  end
  return old
end

function editor:insmode(mode)
  local old = self.insert_mode
  if mode ~= nil then
    self.insert_mode = mode
  end
  return old
end

function editor:selstarted()
  return self.sel.start
end

function editor:select(on, y1, x2, y2)
  local s = self
  if y1 and x2 and y2 then
    s.sel.x, s.sel.y, s.sel.endx, s.sel.endy = on, y1, x2, y2
    s.sel.start = false
    return
  end
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

function editor:selpar()
  local s = self

  local delim = {
    [" "] = true;
    [","] = true;
    ["."] = true;
    [";"] = true;
    ["!"] = true;
    ["("] = true;
    ["{"] = true;
    ["<"] = true;
    ["["] = true;
    [")"] = true;
    ["}"] = true;
    [">"] = true;
    ["]"] = true;
    ["*"] = true;
    ["+"] = true;
    ["-"] = true;
    ["/"] = true;
    ["="] = true;
  }

  local left_delim = {
    ["("] = ")";
    ["{"] = "}";
    ["["] = "]";
    ["<"] = ">";
    ['"'] = '"';
    ["'"] = "'";
  }

  local right_delim = {
    [")"] = "(";
    ["}"] = "{";
    ["]"] = "[";
    [">"] = "<";
    ['"'] = '"';
    ["'"] = "'";
  }
  local x, y = s:cursor()
  local l = s.lines[y]
  local ind

  local function ind_find(l, i, a, b)
    if a == b then
      return l[i] == a
    end
    if l[i] == a then ind = ind + 1
    elseif l[i] == b then ind = ind - 1 end
    return ind == 0
  end

  local c = l[x-1]
  if c and left_delim[c] then
    ind = 1
    for i = x, #l, 1 do
      if ind_find(l, i, c, left_delim[c]) then
        s:selmode()
        s:select(x, y, i, y)
        return
      end
    end
    return
  end

  c = l[x+1]
  if c and right_delim[c] then
    ind = 1
    for i=x, 1, -1 do
      if ind_find(l, i, c, right_delim[c]) then
        s:selmode()
        s:select(i + 1, y, x + 1, y)
        return
      end
    end
    return
  end

  local left, right = 1, #l + 1
  for i = x - 1, 1, -1 do
    if delim[l[i]] then
      left = i + 1
      break
    end
  end
  for i = x + 1, #l, 1 do
    if delim[l[i]] then
      right = i
      break
    end
  end
  s:selmode()
  s:select(left, y, right, y)
end

function editor:wrap()
  local s = self
  local t = s:selected()
  if not t then return end
  t = t:gsub("\n", " ")
  t = t:wrap(s.width)
  local x1, y1 = s:selection()
  s:move(x1, y1)
  s:cut(false, false)
  for _, l in ipairs(t) do
    self:input(l)
    self:newline()
  end
end

function editor:cut(copy, clip)
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
    if y ~= y1 and y ~= y2 and not s:selmode() then -- full line
      clipboard = clipboard .. table.concat(s.lines[yy])..'\n'
    else
      for x=1, #s.lines[yy] do
        if s:insel(x, y) then
          clipboard = clipboard .. s.lines[yy][x]
          if x == #s.lines[yy] or s:selmode() and x == x2 then
            if y ~= y2 then
              clipboard = clipboard .. '\n'
            end
          end
        else
          table.insert(nl, s.lines[yy][x])
        end
      end
    end
    if #nl == 0 and y ~= y2 and not copy then
      table.remove(s.lines, yy)
    else
      s.lines[yy] = copy and s.lines[yy] or nl
      yy = yy + 1
    end
  end
  if not copy then
    s:move(x1, y1)
    s:unselect()
  end
  if clip ~= false then
    sys.clipboard(clipboard)
    s.clipboard = clipboard
  end
  return clipboard
end

function editor:delete()
  local s = self
  local x0, y0 = s:cursor()
  s:left()
  local x, y = s:cursor()
  s:move(x0, y0)
  s:right()
  local x1, y1 = s:cursor()
  s:move(x0, y0)
  if s:insel(x, y) or s:insel(x0, y0) or s:insel(x1, y1) then
    s:cut(false, false)
    return
  end
  s:unselect()
  if s.cur.x <= #s.lines[s.cur.y] then
    s:history()
    table.remove(s.lines[s.cur.y], s.cur.x)
  elseif s.cur.x > #s.lines[s.cur.y] and s.lines[s.cur.y+1] then
    s:history 'start'
    s:history()
    s.cur.y = s.cur.y + 1
    s:history('cut')
    s.hist[#s.hist].rem = 0
    s:history 'end'
    local l = table.remove(s.lines, s.cur.y)
    s.cur.y = s.cur.y - 1
    for _, v in ipairs(l) do
      table.insert(s.lines[s.cur.y], v)
    end
  end
  s:move()
end

local function getind(l)
  if not l then return 0 end
  local ind = 0
  for i=1, #l do
    if l[i] ~= ' ' then break end
    ind = ind + 1
  end
  return ind
end

function editor:newline(indent)
  local s = self
  local ind, ind2 = 0, 0
  s.lines[s.cur.y] = s.lines[s.cur.y] or {}
  local l = s.lines[s.cur.y]
  if s.cur.x > 1 and indent then
    ind, ind2 = getind(l), getind(s.lines[s.cur.y + 1])
    ind = ind > ind2 and ind or ind2
  end
  s:history('newline')
  table.insert(s.lines, s.cur.y + 1, {})
  for i=1, ind do
    table.insert(s.lines[s.cur.y + 1], 1, ' ')
  end
  for k=s.cur.x, #l do
    table.insert(s.lines[s.cur.y+1], table.remove(l, s.cur.x))
  end
  s:unselect()
  s.col = 1
  s:move(ind + 1, s.cur.y + 1)
end

function editor:backspace()
  local s = self
  local x0, y0 = s:cursor()
  s:left()
  local x, y = s:cursor()
  s:move(x0, y0)
  if s:insel(x, y) then
    s:cut(false, false)
    return
  end
  s:unselect()
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
  s:move()
end

function editor:paste(clip)
  local s = self
  local text = clip or sys.clipboard() or s.clipboard or ''
  s:history 'start'
  for l in text:lines(true) do
    local x, y = s:cursor()
    local nl = l:endswith("\n")
    l = l:gsub("\n$", "")
    s:input(l)
    if nl then
      if s:selmode() then -- vertical?
        s:move(x, y + 1)
      else
        s:newline(false)
      end
    end
  end
  s:history 'end'
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
  self:move()
end

function editor:dupline()
  local s = self
  s:history 'newline'
  table.insert(self.lines, self.cur.y, table.clone(self.lines[self.cur.y]))
  self:move()
end

function editor:search(t)
  local s = self
  local cx, cy = s:cursor()
  local x1, x2
  for y = cy, #s.lines do
    local l = table.concat(s.lines[y], '')
    local start = 0
    if y == cy then
      local chars = s.lines[y]
      for i=1,cx + 1 do
        start = start + (chars[i] or ' '):len()
      end
    end
    if l:find(t, start, true) then
      local b, e = l:find(t, start, true)
      local pos = 1
      for i=1,#s.lines[y] do
        if pos == b then
          x1 = i
        end
        pos = pos + s.lines[y][i]:len()
        if pos - 1 == e then
          x2 = i + 1
          break
        end
      end
      if x1 and x2 then
        return x1, y, x2, y
      end
    end
  end
  return false
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
    return nr + self.line - 1, self.col, n > #l and #l or n
  end
end

return editor
