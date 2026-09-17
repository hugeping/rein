local win = require "red/win"
local menu = win:new()

function menu:geom(x, y, w, h)
  win.geom(self, x, y, w, h)
  win.geom(self, x, y, w, self:realheight())
end

-- a menu whose text is set from scratch (a new one, the column menu after
-- a tab switch) keeps the cursor at the end: typed words are appended
function menu:set(text)
  win.set(self, text)
  self:cur(#self.buf.text + 1)
end

function menu:event(r, v, a, b)
  if win.event(self, r, v, a, b) then
    if self:changed() then
      if self.h ~=  self:realheight() then
        self.frame:refresh()
      end
    end
    return true
  end
end

function menu:exec(t)
  local a = t:strip():split(1)
  local w = self:data()
  if w and w.cmd and w.cmd[a[1]] then
    if w.cmd[a[1]](w, a[2]) then
      return true
    end
  end
  if self.cmd and self.cmd[a[1]] then
    if self.cmd[a[1]](self, a[2]) then
      return true
    end
  end
  return win.exec(self, t)
end

-- data window associated with the menu: its own window in stacked,
-- the active window of the frame otherwise
function menu:data()
  return self.win or self.frame:win()
end

function menu:toline(nr)
  local w = self:data()
  if not w then
    return
  end
  return w:toline(nr)
end

function menu:search(text, back)
  local w = self:data()
  if not w or not w.buf then
    return
  end
  if w.buf:issel() then
    local t = w:get_active_text()
    if t == text then
      return w:search(t, back)
    else
      w.buf:resetsel()
    end
  end
  return w:search(text, back)
end

function menu:get_active_text(_)
  return win.get_active_text(self, true)
end

function menu:dirty()
end

return menu
