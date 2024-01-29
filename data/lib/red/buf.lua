local buf = {
  history_len = 256;
}

function buf:new(fname)
  local b = { cur = 1, fname = fname,
    hist = {}, redo_hist = {}, sel = {}, text = {} }
  self.__index = self
  setmetatable(b, self)
  return b
end

function buf:gettext(s, e)
  if s or e then
    local t = {}
    for i = (s or 1), (e or #self.text) do
      table.insert(t, self.text[i] or '')
    end
    return table.concat(t, '')
  end
  return table.concat(self.text, '')
end

function buf:changed(fl)
  local c = self.is_changed
  if fl ~= nil then
    self.is_changed = fl
  end
  return c
end

--[[
local hist_delim = {
  [" "] = true,
  ["\n"] = true,
}
]]--

function buf:history(op, pos, nr, append)
  local text
  self:changed(true)
  pos = pos or self.cur
  if op == 'input' then
    text = nr
    nr = #nr
  end
  nr = nr or 1
  local h = self.hist[#self.hist]
  if not append or not h or h.op ~= op or op ~= 'input' or pos ~= h.pos + h.nr then
    h = { op = op, pos = pos, nr = nr, cur = self.cur }
    table.insert(self.hist, h)
  else
    h.nr = h.nr + nr
  end
  if #h > self.history_len then
    table.remove(self.hist, 1)
  end
  if op == 'cut' then
    self.redo_hist = {}
    h.data = {}
    for i = 1, nr do
      table.insert(h.data, self.text[i + pos - 1])
    end
  elseif op == 'input' then
    self.redo_hist = {}
    h.data = {}
    for i = 1, nr do
      table.insert(h.data, text[i])
    end
  end
  return h
end

function buf:redo()
  if #self.redo_hist == 0 then return end
  self:changed(true)
  self:resetsel()
  local depth = 0
  repeat
    local h = table.remove(self.redo_hist, 1)
    if not h then break end
    self.cur = math.min(h.cur, #self.text + 1)
    table.insert(self.hist, h)
    if h.op == 'start' then
      depth = depth + 1
    elseif h.op == 'end' then
      depth = depth - 1
    elseif h.op == 'input' then
      for i = 1, h.nr do
        table.insert(self.text, h.pos + i - 1, h.data[i])
        self.cur = self.cur + 1
      end
    elseif h.op == 'cut' then
      local new = {}
      for i = 1, #self.text do
        if i < h.pos or i >= h.pos + h.nr then
          table.insert(new, self.text[i])
        end
      end
      self.text = new
    end
  until depth == 0
end

function buf:undo()
  if #self.hist == 0 then return end
  self:changed(true)
  self:resetsel()
  local depth = 0
  repeat
    local h = table.remove(self.hist, #self.hist)
    if not h then break end
    table.insert(self.redo_hist, 1, h)
    if h.op == 'start' then
      depth = depth + 1
    elseif h.op == 'end' then
      depth = depth - 1
    elseif h.op == 'cut' then
      for i = 1, h.nr do
        table.insert(self.text, h.pos + i - 1, h.data[i])
      end
    elseif h.op == 'input' then
      local new = {}
      for i = 1, #self.text do
        if i < h.pos or i >= h.pos + h.nr then
          table.insert(new, self.text[i])
        end
      end
      self.text = new
    end
    self.cur = math.min(h.cur, #self.text + 1)
  until depth == 0
end

function buf:backspace()
  if self:issel() then
    return self:cut()
  end
  if self.cur <= 1 then return end
  self:history('cut', self.cur - 1)
  table.remove(self.text, self.cur - 1)
  self.cur = self.cur - 1
end

function buf:delete()
  if self:issel() then
    return self:cut()
  end
  if self.cur > #self.text then
    return
  end
  self:right()
  self:backspace()
end

function buf:kill()
  local start = self.cur
  self:lineend()
  if self.cur == start then
    self:delete()
  else
    self:setsel(start, self.cur)
    self:cut()
  end
end

function buf:sel_line(whole)
  self:linestart()
  local start = self.cur
  self:lineend()
  if self.text[self.cur] == '\n' and whole then
    self:setsel(start, self.cur + 1)
  else
    self:setsel(start, self.cur)
  end
end


local function is_space(t)
  return t == ' ' or t == '\t'
end

local function scan_spaces(self, pos, max)
  local c
  local pre = ''
  for i = pos, max do
    c = self.text[i]
    if is_space(c) then
      pre = pre .. c
    else
      break
    end
  end
  return pre
end

function buf:newline()
  local cur = self.cur
  local pre = ''
  if true then -- not is_space(self.text[cur]) then
    self:linestart()
    local p1 = scan_spaces(self, self.cur, cur-1)
    self:lineend()
    local p2 = scan_spaces(self, self.cur + 1, #self.text)
    pre = p1
    if p2:len() > p1:len() and cur == self.cur then
      pre = p2
    end
  end
  self.cur = cur
  self:input('\n'..pre)
end

function buf:setsel(s, e)
  self.sel.s, self.sel.e = s, e
end

function buf:issel()
  return (self.sel.s and self.sel.s ~= self.sel.e)
end

function buf:getsel()
  return self.sel
end

function buf:range()
  if self:issel() then
    local s, e = self:selrange()
    return s, e - 1
  end
  return 1, #self.text
end

function buf:selrange()
  local s, e = self.sel.s, self.sel.e
  if s > e then s, e = e, s end
  return s, e
end

function buf:getseltext()
  if not self:issel() then return '' end
  local s, e = self:selrange()
  return self:gettext(s, e - 1)
end

function buf:resetsel()
  self.sel.s, self.sel.e = nil, nil
end

function buf:searchpos(pos, e, text, back)
  local fail
  local delta = 1
  local ws, we = 1, #text
  if back then
    delta = -1
    ws, we = #text, 1
  end
  for i = pos, e, delta do
    fail = false
    for k = ws, we, delta do
      if self.text[i + k - 1] ~= text[k] then
        fail = true
        break
      end
    end
    if not fail then
      self.cur = i
      self:setsel(i, i + #text)
      return true
    end
  end
end

function buf:search(text, back)
  if type(text) == 'string' then
    text = utf.chars(text)
  end
  if back then
    return self:searchpos(self.cur - 1, 1, text, true)
  end
  return self:searchpos(self.cur, #self.text, text) or
    self:searchpos(1, self.cur, text)
end

function buf:cut(copy)
  if not self:issel() then
    return
  end
  local s, e = self:selrange()
  if not copy then
    self:history('cut', s, e - s)
  end
  local cl = {}
  local clip
  for i = s, e - 1 do
    table.insert(cl, self.text[i])
  end
  clip = table.concat(cl, '')
  if not copy then
    local new = {}
    for i = 1, #self.text do
      if i < s or i >= e then
        table.insert(new, self.text[i])
      end
    end
    self.text = new
  end
  if copy ~= false then
    sys.clipboard(clip)
    self.clipboard = clip
  end
  if not copy then
    self.cur = s
    self:resetsel()
  end
end

function buf:insel(cur)
  if not self:issel() then return end
  cur = cur or self.cur
  local s, e = self:selrange()
  return cur >= s and cur < e
end

function buf:paste()
  local clip = sys.clipboard() or self.clipboard
  if clip then
    clip = clip:gsub("\r", "") -- Windows?
  end
--  local start = self:issel() and self:selrange() or self.cur
  self:input(clip)
--  self:setsel(start, self.cur)
end

function buf:insmode(over)
  local o = self.over_mode
  if over ~= nil then
    self.over_mode = over
  end
  return o
end

function buf:input(txt)
  if self.cur < 1 then return end
  local over_mode = self.over_mode
  local sel = self:issel()
  if sel or self.text[self.cur] == '\n' or
    not self.text[self.cur] or txt == '\n' then
    over_mode = false
  end
  local u = type(txt) == 'table' and txt or utf.chars(txt)
  if sel then
    self:history 'start'
    self:cut(false)
  elseif over_mode then
    self:history 'start'
    self:history('cut', self.cur, #u)
  end
  self:history('input', self.cur, u)--, #u == 1 and not hist_delim[u[1]])
  local text = self.text
  local rebuild
  if #u > 512 and not over_mode then
    rebuild = true
    text = {}
    for i = 1, self.cur - 1 do
      table.insert(text, self.text[i])
    end
  end
  local cur = self.cur
  for i = 1, #u do
    if over_mode then
      text[self.cur] = u[i]
    else
      if rebuild then
        table.insert(text, u[i])
      else
        table.insert(text, self.cur, u[i])
      end
    end
    self.cur = self.cur + 1
  end
  if rebuild then
    for i = cur, #self.text do
      table.insert(text, self.text[i])
    end
    self.text = text
  end
  if sel or over_mode then
    self:history 'end'
  end
end

function buf:nextline(pos)
  for i = (pos or self.cur), #self.text do
    if self.text[i] == '\n' then
      self.cur = i + 1
      break
    end
  end
  return self.cur
end

function buf:linestart(pos)
  for i = (pos or self.cur), 1, -1 do
    self.cur = i
    if self.text[i-1] == '\n' then
      break
    end
  end
  return self.cur
end

function buf:lineend(pos)
  for i = (pos or self.cur), #self.text do
    if self.text[i] == '\n' then
      break
    end
    self.cur = i + 1
  end
  return self.cur
end

function buf:prevline()
  self:linestart()
  self:left()
  self:linestart()
end

function buf:left()
  self.cur = math.max(1, self.cur - 1)
end

function buf:right()
  self.cur = math.min(self.cur + 1, #self.text + 1)
end

function buf:set(text)
  if type(text) == 'string' then
    self.text = utf.chars(text)
  else
    self.text = text
  end
  self:resetsel()
  self.cur = math.min(#self.text + 1, self.cur)
end

function buf:tail()
  self.cur = #self.text + 1
end

function buf:append(text, cur)
  local u = utf.chars(text)
  for i = 1, #u do
    table.insert(self.text, u[i])
  end
  if cur then
    self:tail()
  end
end

local sel_delim = {
  [" "] = true, [","] = true, ["."] = true,
  [";"] = true, ["!"] = true, ["("] = true,
  ["{"] = true, ["<"] = true, ["["] = true,
  [")"] = true, ["}"] = true, [">"] = true,
  ["]"] = true, ["*"] = true, ["+"] = true,
  ["-"] = true, ["/"] = true, ["="] = true,
  ["&"] = true, ["^"] = true, ["~"] = true,
  ["\t"] = true, ["\n"] = true, [":"] = true,
}

local left_delim = {
  ["("] = ")", ["{"] = "}",
  ["["] = "]", ["<"] = ">",
  ['"'] = '"', ["'"] = "'",
}

local right_delim = {
  [")"] = "(", ["}"] = "{",
  ["]"] = "[", [">"] = "<",
  ['"'] = '"', ["'"] = "'",
}

function buf:selpar(delim)
  delim = delim or sel_delim

  local ind

  local function ind_match(c, a, b)
    if a == b then
      return c == a
    end
    if c == a then ind = ind + 1
    elseif c == b then ind = ind - 1 end
    return ind == 0
  end

  local function ind_scan(c, delims, pos, dir)
    if not c or not delims[c] then
      return
    end
    ind = 1
    local e = dir == 1 and #self.text or 1
    for i = pos, e, dir do
      if ind_match(self.text[i], c, delims[c]) then
        if dir == 1 then
          self:setsel(pos, i)
        else
          self:setsel(i + 1, pos + 1)
        end
        return true, c ~= delims[c]
      end
    end
  end

  local r, v = ind_scan(self.text[self.cur-1], left_delim, self.cur, 1)
  if v then
    return
  elseif ind_scan(self.text[self.cur], right_delim, self.cur - 1, -1) then
    return
  elseif r then
    ind_scan(self.text[self.cur-1], left_delim, self.cur, 1)
    return
  end

  if self.text[self.cur] == '\n' then -- whole line
    self:sel_line()
    return
  end

  local left, right = 1, #self.text + 1

  for i = self.cur - 1, 1, -1 do
    if delim[self.text[i]] then
      left = i + 1
      break
    end
  end

  for i = self.cur, #self.text, 1 do
    if delim[self.text[i]] then
      right = i
      break
    end
  end
  self:setsel(left, right)
end

function buf:hash()
  local hval = 0x811c9dc5
  for i=1, #self.text do
    hval = bit.band((hval * 0x01000193), 0xffffffff)
    hval = bit.bxor(hval, utf.codepoint(self.text[i]))
  end
  return hval
end

function buf:dirty(fl)
  if fl == nil then -- fast path
    return #self.text ~= self.written_len or
      self:hash() ~= self.written
  end

  local hash = self:hash()
  local last = self.written
  if fl == false then
     self.written = hash
     self.written_len = #self.text
  elseif fl == true then
     self.written = false
     self.written_len = false
  end
  return hash ~= last
end

function buf:save_atomic(fname)
  self.fname = fname or self.fname
  local r
  local f, e = io.open(self.fname..'.red', "wb")
  if not f then
    return f, e
  end
  r, e = f:write(self:gettext())
  if not r then return r, e end
  r, e = f:close()
  if not r then return r, e end
  r, e = os.rename(self.fname..'.red', self.fname)
  if not r then return r, e end
  self:dirty(false)
  return true
end

function buf:save(fname)
  self.fname = fname or self.fname
  local r, f, e
  f, e = io.open(self.fname, "wb")
  if not f then
    return f, e
  end
  r, e = f:write(self:gettext())
  if not r then return r, e end
  r, e = f:close()
  if not r then return r, e end
  self:dirty(false)
  return true
end

function buf:load(fname)
  fname = fname or self.fname
  local f, e = io.open(fname, "rb")
  if not f then
    return f, e
  end
  self.fname = fname
  self.hist = {}
  self.redo_hist = {}
  self.text = {}
  for l in f:lines() do
    local u = utf.chars(l)
    for i = 1, #u do
      table.insert(self.text, u[i])
    end
    table.insert(self.text, "\n")
  end
  self:dirty(false)
  f:close()
  return true
end

function buf:loadornew(fname)
  if not self:load(fname) then
    self.fname = fname
    self:dirty(true)
    return false
  end
  return true
end

function buf:line_nr()
  local line = 1
  local line_pos = 1
  for i = 1, #self.text do
    if i >= self.cur then return line, i - line_pos end
    if self.text[i] == '\n' then
      line = line + 1
      line_pos = i + 1
    end
  end
  return line, self.cur - line_pos
end

function buf:toline(nr)
  local line = 1
  local found
  for i = 1, #self.text do
    self.cur = i
    if line >= nr then found = true break end
    if self.text[i] == '\n' then line = line + 1 end
  end
  if not found then
    self.cur = #self.text + 1
  else
    self:linestart()
  end
  return found
end

function buf:isfile()
  return self.fname and not self.fname:endswith '/' and not
    self.fname:startswith '+'
end

function buf:isdir()
  return self.fname and self.fname:endswith '/' and not
    self.fname:startswith '+'
end

return buf
