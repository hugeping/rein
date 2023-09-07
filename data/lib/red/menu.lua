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
  if self.cmd and self.cmd[t] then
    if self.cmd[t](self, t) then
      return true
    end
  end
  return win.exec(self, t)
end

function menu:toline(nr)
  local c = self.frame:menu()
  if not c then
    return
  end
  return c:toline(nr)
end

function menu:search(text, back)
  local c = self.frame:win()
  if not c or not c.buf then
    return
  end
  if c.buf:issel() then
    local t = c:get_active_text()
    if t == text then
      return c:search(t, back)
    else
      c.buf:resetsel()
    end
  end
  return c:search(text, back)
end

function menu:get_active_text(_)
  return win.get_active_text(self, true)
end

function menu:dirty()
end

return menu
