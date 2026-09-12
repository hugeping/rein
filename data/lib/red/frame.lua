local conf = require "red/conf"

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

-- the main (top, mainwin) frame this frame belongs to
function frame:main()
  return self.frame and self.frame:main() or self
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

function frame:close_win(w)
  if not w then return end
  local k = self:find_win(w)
  if not k or k < 1 then
    return -- not a window of this frame (menu?)
  end
  if w.buf:isfile() and w:dirty() and not w:clean() then
    self:err("File %q is not saved!", w.buf.fname)
    w:clean(true)
  else
    w:killproc()
    self:del(w)
  end
  self:update(true, true)
  self:refresh()
end

function frame:open_err(name)
  -- in stacked mode new service windows go to the end, not to the top
  local pos
  if self.stacked then
    pos = self:win_nr() + 1
  end
  local w = self:file(name or '+Errors', pos)
  if not w then return end
  w:tail()
  return w
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
    screen:clear(x, y, w, h, conf.void_bg)
  end
end

-- body heights for the stacked windows, fitting `h` pixels after menu bars
function frame:stacked_sizes(h)
  local n = self:win_nr()
  self:frac_norm()
  local total_mh = 0
  for c in self:for_win() do
    local cm = self:cmd_menu(c)
    if cm then
      if not cm.cols then
        cm:geom(self.x or 0, self.y or 0, self.w or 0, 0)
      end
      total_mh = total_mh + cm:realheight()
    end
  end
  local flexible = math.max(0, h - total_mh)
  self.flexible = flexible
  local sizes = {}
  local used = 0
  for c, i in self:for_win() do
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
    sizes[i] = bh
  end
  return flexible, sizes
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
      screen:clear(x, y, w, h, conf.void_bg)
    end
    return
  end
  local _, sizes = self:stacked_sizes(h)
  for c, i in self:for_win() do
    local cm = self:cmd_menu(c)
    local mh = cm and cm:realheight() or 0
    local bh = sizes[i]
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
    screen:clear(x, y, w, h, conf.void_bg)
  end
end

-- keep per-window vertical fractions normalized to 1
function frame:frac_norm()
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

-- shift the boundary between w and the previous one by d pixels;
-- `total` is the full size in pixels, `min_px` the minimum side size
function frame:resize_frac(w, d, total, min_px)
  local idx = self:find_win(w)
  if not idx or idx <= 1 or not total or total <= 0 then
    return
  end
  local prev = self:win(idx - 1)
  if not prev then
    return
  end
  local pf = prev.frac or (1 / self:win_nr())
  local cf = w.frac or (1 / self:win_nr())
  local sum = pf + cf
  local minf = math.min((min_px or 0) / total, sum / 2)
  local nf = math.max(minf, math.min(sum - minf, pf + d / total))
  prev.frac = nf
  w.frac = sum - nf
  self:refresh()
end

-- drag the boundary between w and the window above it by dy pixels
function frame:resize_win(w, dy)
  self:resize_frac(w, dy, self.flexible, 0)
end

function frame:update()
end

local function hit(obj, r, v, a, b)
  if obj and obj:event(r, v, a, b) then
    if obj.buf and obj:changed(false) then
      obj:dirty(obj.buf:dirty())
      obj.frame:update()
    end
    return true
  end
end

function frame:event(r, v, a, b)
  -- a press on a menu square (resize with LMB, move with RMB) is
  -- handled before the childs
  if self.press and self:press_event(r, v, a, b) then
    return true
  end
  if self.stacked then
    return self:event_stacked(r, v, a, b)
  end
  for _, c in ipairs(self.childs) do
    if hit(c, r, v, a, b) then
      break
    end
  end
end

function frame:event_stacked(r, v, a, b)
  if hit(self:menu(), r, v, a, b) then
    return
  end
  for i = 2, #self.childs do
    local c = self.childs[i]
    if not c then break end
    if hit(c.menu_w, r, v, a, b) or hit(c, r, v, a, b) then
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

-- insertion index (1..n+1) for dropping a window at y: the window is
-- placed right below the window whose slot (menu + body) contains y
function frame:win_at(y)
  local n = self:win_nr()
  if not self.stacked then
    return 1
  end
  for c, i in self:for_win() do
    local cm = self:cmd_menu(c)
    local top = cm and cm.y or c.y
    if y < top then
      return i
    end
  end
  return n + 1
end

function frame:win_nr()
  return math.max(0, #self.childs - 1)
end

function frame:menu()
  return self.childs[1]
end

-- menu which holds the command line for window (or menu) w:
-- its own menu in stacked mode, the frame menu in tabbed
function frame:cmd_menu(w)
  local k = w.win or w
  local i = self:find_win(k)
  if self.stacked and i and i > 0 then
    if not k.menu_w then
      k.menu_w = self:new_win_menu(k)
    end
    return k.menu_w
  end
  return self:menu()
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
        c.menu = c.menu_w:gettext()
      end
    end
  else
    -- expand to stack: carry the column menu tail over to the active
    -- window's own menu, then restore the column command line
    local w = self:win()
    if w then
      local cur = self:menu():gettext()
      local tail = frame.menu_tail(cur)
      if tail then
        w.menu = frame.menu_set_tail(w.menu, tail)
        if w.menu_w then
          w.menu_w:set(frame.menu_set_tail(w.menu_w:gettext(), tail))
        end
      end
      self:menu():set(frame.menu_set_tail(cur,
        self.stacked_cmdline or conf.emptymenu))
    end
  end
  self.stacked = not self.stacked
  self:update(true, true)
  self:refresh()
end

return frame
