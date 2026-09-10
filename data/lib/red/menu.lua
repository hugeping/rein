local win = require "red/win"
local menu = win:new()

function menu:geom(x, y, w, h)
  win.geom(self, x, y, w, h)
  win.geom(self, x, y, w, self:realheight())
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
  local w = self:winmenu()
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

function menu:toline(nr)
  local w = self:winmenu()
  if not w then
    return
  end
  return w:toline(nr)
end

function menu:search(text, back)
  local w = self:winmenu()
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
