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
  self:stacked_norm()
  local total_mh = 0
  for c in self:for_win() do
    local cm = self:win_menu(c)
    if cm then
      if not cm.cols then
        cm:geom(x, y, w, 0)
      end
      total_mh = total_mh + cm:realheight()
    end
  end
  local flexible = math.max(0, h - total_mh)
  self.flexible = flexible
  local used = 0
  for c, i in self:for_win() do
    local cm = self:win_menu(c)
    local mh = cm and cm:realheight() or 0
    local bh
    if i == n then
      bh = flexible - used
    else
      bh = math.floor(flexible * (c.frac or (1 / n)))
      used = used + bh
    end
    if bh < 0 then
      bh = 0
    end
    if h > 0 then
      if cm then
        cm:geom(x, y, w, mh + bh)
        y = y + cm.h
      end
      c:geom(x, y, w, bh)
      y = y + c.h
      h = h - mh - bh
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

-- keep per-window vertical fractions normalized to 1
function frame:stacked_norm()
  local n = self:win_nr()
  if n == 0 then
    return
  end
  local sum, missing = 0, 0
  for c in self:for_win() do
    if c.frac then
      sum = sum + c.frac
    else
      missing = missing + 1
    end
  end
  if missing == 0 then
    if sum <= 0 or math.abs(sum - 1) < 0.0001 then
      return
    end
  else
    local def = 1 / n
    for c in self:for_win() do
      if not c.frac then
        c.frac = def
        sum = sum + def
      end
    end
  end
  if sum > 0 then
    for c in self:for_win() do
      c.frac = c.frac / sum
    end
  end
end

-- drag the boundary between w and the window above it by dy pixels
function frame:resize_win(w, dy)
  local idx = self:find_win(w)
  if not idx or idx <= 1 then
    return
  end
  local flexible = self.flexible
  if not flexible or flexible <= 0 then
    return
  end
  local prev = self:win(idx - 1)
  if not prev then
    return
  end
  local pf = prev.frac or (1 / self:win_nr())
  local cf = w.frac or (1 / self:win_nr())
  local total = pf + cf
  local nf = math.max(0, math.min(total, pf + dy / flexible))
  prev.frac = nf
  w.frac = math.max(0, total - nf)
  self:refresh()
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
  if self.rz_menu then
    if r == 'mousemotion' then
      local _, _, mb = input.mouse()
      if not mb.left then
        self.rz_menu = nil
      else
        if not self.rz_active and math.abs(a - self.rz_start) >= 4 then
          self.rz_active = true
          self.rz_menu.autoscroll_on = false
        end
        if self.rz_active then
          self:resize_win(self.rz_win, a - self.rz_last)
          self.rz_last = a
        end
      end
      return
    elseif r == 'mouseup' then
      self.rz_menu = nil
      return
    end
  end
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

function frame.menu_tail(s)
  if not s then return end
  local d = s:find('|', 1, true)
  if d then
    return s:sub(d)
  end
end

function frame.menu_set_tail(s, tail)
  local d = s and s:find('|', 1, true)
  if s and d then
    return s:sub(1, d - 1) .. tail
  end
  return (s and s .. ' ' or '') .. tail
end

function frame:stacked_toggle()
  if self.stacked then
    -- collapse to tabbed: remember the column command line and save
    -- every window's own command line (its per-window menu) so it
    -- reappears in the column menu later
    self.stacked_cmdline = frame.menu_tail(self:menu():gettext()) or '|'
    for c in self:for_win() do
      if c.menu_w then
        self:sync_win_menu(c)
        c.menu = c.menu_w:gettext()
      end
    end
  else
    -- expand to stack: carry the column menu tail over to the active
    -- window's own menu, then clear the column menu's command line
    local w = self:win()
    if w then
      local cur = self:menu():gettext()
      local tail = frame.menu_tail(cur)
      if tail then
        w.menu = frame.menu_set_tail(w.menu, tail)
        self:menu():set(frame.menu_set_tail(cur, '|'))
      end
    end
  end
  self.stacked = not self.stacked
  if self.stacked and self.stacked_cmdline then
    -- restore the column command line last used in stacked mode
    self:menu():set(frame.menu_set_tail(self:menu():gettext(),
      self.stacked_cmdline))
  end
  self:update(true, true)
  self:refresh()
end

return frame
