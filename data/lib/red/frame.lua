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
  return self:win()
end

function frame:err(fmt, ...)
  local w = self:open_err()
  w:append(string.format(fmt..'\n', ...))
end

function frame:process()
  local status
  for _, v in ipairs(self.childs) do
    local r, e = v:process()
    if r == false then
      self:err(e)
    elseif r == true then
      status = true
    end
  end
  return status
end

function frame:refresh()
  self:geom(self.x, self.y, self.w, self.h)
end

function frame:geom(x, y, w, h)
  self.x, self.y, self.w, self.h = x, y, w, h
  if #self.childs == 0 then
    return
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

function frame:update()
end

function frame:event(r, v, a, b)
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

return frame
