return {
  { 'home',
    function(self)
      self:linestart()
    end
  },
  { 'insert',
    function(self)
      self.buf:insmode(not self.buf:insmode())
    end
  },
  { 'end',
    function(self)
      self:lineend()
    end
  },
  { 'escape',
    function(self)
      self:escape()
    end
  },
  { 'ctrl+home',
    function(self)
      self:cur(1)
      self:visible()
    end
  },
  { 'ctrl+escape',
    function(self)
      self:setsel(1, #self.buf.text+1)
    end
  },
  { 'ctrl+end',
    function(self)
      self:cur(#self.buf.text)
      self:lineend()
      self:visible()
    end
  },
  { 'ctrl+s',
    function(self)
      self:save()
      self.frame:update()
    end
  },
  { 'ctrl+w',
    function(self)
      self.frame:menu():exec 'Close'
    end
  },
  { 'ctrl+o',
    function(self)
      self.frame:push_win(self.frame:win(self.frame.prev_win or 2)
        or self.frame:win(2))
    end
  },
  {
    'alt+w',
    function(self)
      self:selpar()
    end
  },
  { 'ctrl+b',
    function(self)
      local m = self.frame:menu()
      local t = string.format(":%d ", self.buf:line_nr())
      if m.buf.text[#m.buf.text] ~= ' ' then
        t = ' ' .. t
      end
      m:append(t)
    end
  },
}
