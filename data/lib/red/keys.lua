local proc = require "red/proc"
return {
  { 'shift+home',
    function(self)
      self:linestart()
      self:movesel()
    end
  },
  { 'home',
    function(self)
      self:linestart()
    end
  },
  { 'end',
    function(self)
      self:lineend()
    end
  },
  { 'shift+end',
    function(self)
      self:lineend()
      self:movesel()
    end
  },
  { 'insert',
    function(self)
      self.buf:insmode(not self.buf:insmode())
    end
  },
  { 'escape',
    function(self)
      self:escape()
    end
  },
  {
    'ctrl+]',
    function(self)
      self.frame:menu():exec 'i+'
    end
  },
  {
    'ctrl+[',
    function(self)
      self.frame:menu():exec 'i-'
    end
  },
  { 'ctrl+escape',
    function(self)
      self:setsel(1, #self.buf.text+1)
    end
  },
  { 'ctrl+home',
    function(self)
      self:cur(1)
      self:visible()
    end
  },
  { 'ctrl+end',
    function(self)
      self:cur(#self.buf.text)
      self:lineend()
      self:visible()
    end
  },
  { 'shift+ctrl+home',
    function(self)
      self:cur(1)
      self:visible()
      self:movesel()
    end
  },
  { 'shift+ctrl+end',
    function(self)
      self:cur(#self.buf.text)
      self:lineend()
      self:visible()
      self:movesel()
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
      self.frame:update()
      self.frame:refresh()
    end
  },
  { 'alt+b',
    function(self)
      local fr = self.frame.frame and self.frame.frame or self.frame
      local m = fr:menu()
      local t = string.format("%s:%d ", self.buf.fname or '', self.buf:line_nr())
      if m.buf.text[#m.buf.text] ~= ' ' then
        t = ' ' .. t
      end
      m:append(t)
      fr:update()
      fr:refresh()
    end
  },
  { 'alt+v',
    function(self)
      if PLATFORM ~= 'Windows' then
        self:run(proc['<'], 'xclip -o -selection clipboard')
      end
    end
  },
  { -- completion via global
    'alt+f',
    function(self)
      if PLATFORM == 'Windows' then
        return {}
      end
      self:compl(function(_, txt)
        local ret = {}
        local f, _ = io.popen(string.format("global -t -c %q", txt), "r")
        if not f then return ret end
        for l in f:lines() do
          table.insert(ret, l)
        end
        f:close()
        return ret
      end)
    end
  }
}
