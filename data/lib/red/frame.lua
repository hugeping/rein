local frame = {
}

function frame:new(...)
  local f = {
    childs = {}
  }
  self.__index = self
  setmetatable(f, self)
  for _, c in ipairs {...} do
    f:add(c)
  end
  return f
end

function frame:add(child, pos)
  child.frame = self
  if pos then
    table.insert(self.childs, pos, child)
  else
    table.insert(self.childs, child)
  end
end

function frame:del(child)
  if type(child) == 'number' then
    return table.remove(self.childs, child)
  else
    return table.del(self.childs, child)
  end
end

function frame:show()
  for _, v in ipairs(self.childs) do
    v:show()
  end
end

function frame:open_err(name)
  self:file(name or '+Errors')
  self:win():tail()
  return self:win()
end

function frame:err(fmt, ...)
  local w = self:open_err()
  w:append(string.format(fmt..'\n', ...), true)
end

function frame:process()
  local hz
  for _, v in ipairs(self.childs) do
    local r, e = v:process()
    if r == false then
      self:err(e)
    elseif r then
      hz = (not hz or r < hz) and r or hz
    end
  end
  return hz
end

function frame:refresh()
  self:geom(self.x, self.y, self.w, self.h)
end

function frame:geom(x, y, w, h)
  self.x, self.y, self.w, self.h = x, y, w, h
  if #self.childs == 0 then
    return
  end
  if self.stacked then
    return self:geom_stacked(x, y, w, h)
  end
  for _, c in ipairs(self.childs) do
    if h > 0 then
      c:geom(x, y, w, h)
      y = y + c.h
      h = h - c.h
    else
      c:geom(x, y, 0, 0) -- invisible
    end
  end
  if h > 0 then
    screen:clear(x, y, w, h, 7)
  end
end

function frame:geom_stacked(x, y, w, h)
  local m = self:menu()
  if h > 0 then
    m:geom(x, y, w, h)
    y = y + m.h
    h = h - m.h
  end
  local n = self:win_nr()
  if n == 0 then
    if h > 0 then
      screen:clear(x, y, w, h, 7)
    end
    return
  end
  local wh = math.floor(h / n)
  for i = 2, #self.childs do
    local c = self.childs[i]
    local cm = self:win_menu(c)
    if h > 0 then
      local ch = wh
      if cm then
        cm:geom(x, y, w, ch)
        ch = ch - cm.h
        y = y + cm.h
        h = h - cm.h
      end
      c:geom(x, y, w, math.max(0, ch))
      y = y + c.h
      h = h - c.h
    else
      if cm then
        cm:geom(x, y, 0, 0)
      end
      c:geom(x, y, 0, 0) -- invisible
    end
  end
  if h > 0 then
    screen:clear(x, y, w, h, 7)
  end
end

function frame:update()
end

function frame:event(r, v, a, b)
  if self.stacked then
    return self:event_stacked(r, v, a, b)
  end
  for _, c in ipairs(self.childs) do
    if c:event(r, v, a, b) then
      if c:changed(false) then
        c:dirty(c.buf:dirty())
        c.frame:update()
      end
      break
    end
  end
end

function frame:event_stacked(r, v, a, b)
  local function hit(obj)
    if obj and obj:event(r, v, a, b) then
      if obj:changed(false) then
        obj:dirty(obj.buf:dirty())
        obj.frame:update()
      end
      return true
    end
  end
  if hit(self:menu()) then
    return
  end
  for i = 2, #self.childs do
    local c = self.childs[i]
    if not c then break end
    if hit(c.menu_w) or hit(c) then
      return
    end
  end
end

function frame:win(nr)
  return self.childs[(nr or 1) + 1]
end

function frame:del_win(c)
  c = c or 1
  if type(c) == 'number' then
    c = c + 1
  end
  return self:del(c)
end

function frame:add_win(w, c)
  if type(c) == 'number' then
    c = c + 1
  end
  if w.menu_w then
    w.menu_w.frame = self
  end
  return self:add(w, c)
end

function frame:for_win()
  local i = 1
  local n = #self.childs
  return function()
    i = i + 1
    if i > n then
      return
    end
    return self.childs[i], i - 1
  end
end

function frame:find_win(w)
  local idx = table.find(self.childs, w)
  if idx then idx = idx - 1 end
  return idx
end

function frame:win_nr()
  return math.max(0, #self.childs - 1)
end

function frame:menu()
  return self.childs[1]
end

function frame:win_menu(w)
  if not w.menu_w then
    w.menu_w = self:new_win_menu(w)
  end
  return w.menu_w
end

function frame:new_win_menu()
end

function frame:stacked_toggle()
  self.stacked = not self.stacked
  self:update(true, true)
  self:refresh()
end

return frame
