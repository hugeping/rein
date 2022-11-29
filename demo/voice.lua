local sfx = require 'sfx'
gfx.win(384, 384)
mixer.volume(0.5)

local chans = { notes = {}, times = {}, max = 10 } -- number of fingers :)

local W, H = screen:size()

local win = {
  padding = 1.2,
  border = false,
  x = 0,
  y = 0,
  w = W,
  h = H,
  fg = 0,
  bg = 16,
  lev = 0,
  font = font,
  childs = {},
}

function win:new(w)
  w.childs = w.childs or {}
  setmetatable(w, self)
  self.__index = self
  return w
end

local edit = win:new { value = '' }

function edit:edline(r, v, ...)
  if r == 'text' then
    self.value = self.value .. v
--    if self.onedit then self:onedit() end
    return true
  elseif r == 'keydown' then
    if v == 'backspace' then
      local t = utf.chars(self.value)
      table.remove(t, #t)
      self.value = table.concat(t)
    elseif v == 'return' then
      self.edit = false
      if self.onedit then self:onedit() end
    end
    return true
  end
end

function edit:event(r, v, ...)
  local m = self:mevent(r, v, ...)
  if not m then
    if r == 'mousedown' then
      self.edit = false
      if self.onedit then self:onedit() end
    elseif self.edit and self:edline(r, v, ...) then
      return true
    end
    return win.event(self, r, v, ...)
  end
  if m == 'mouseup' then
    self.edit = true
    return true
  end
end

function edit:show()
  win.show(self)
  local w, h = self.font:size(self.value .. (self.edit and '|' or ''))
  local x, y = self:realpos()
  screen:offset(x, y)
  if not self.value:empty() or self.edit then
    screen:clip(x, y, x + self.w, y + self.h)
    local xoff = (self.w - w)/2
    if xoff < 0 then xoff = self.w - w end
    self.font:text(self.value .. (self.edit and '|' or ''), self.fg):
      blend(screen, xoff, (self.h -h)/2)
    screen:noclip()
  end
  screen:nooffset()
end

local label = win:new { }

function label:adjust()
  local w, h = self.font:size(self.text)
  self.w, self.h = w, h
  return self
end

function label:show()
  win.show(self)
  local w, h = self.font:size(self.text)
  local x, y = self:realpos()
  if w == 0 then return end
  screen:offset(x, y)
  screen:clip(x, y, x + self.w, y + self.h)
  local xoff, yoff = (self.w - w)/2, (self.h - h)/2
  if self.left then xoff = 0 end
  self.font:text(self.text or ' ', self.fg):
  blend(screen, xoff, yoff)
  screen:noclip()
  screen:nooffset()
end

local button = label:new { }

function button:event(r, v, ...)
  if self.active and r == 'mouseup' then
    self.active = false
    if self.onclick then self:onclick() end
    return true
  end
  local m = self:mevent(r, v, ...)
  if not m then
    return win.event(self, r, v, ...)
  end
  if m == 'mousedown' then
    self.active = true
  end
  return true
end

function button:show()
  if self.active or self.selected then
    self.fg, self.bg = self.bg, self.fg
    label.show(self)
    self.fg, self.bg = self.bg, self.fg
  else
    label.show(self)
  end
end

function win:with(w)
  for _, v in ipairs(w) do
    table.insert(self.childs, v)
    v.parent = self
  end
  return self
end

function win:realpos()
  local s = self
  local x, y = 0, 0
  repeat
    x = x + s.x
    y = y + s.y
    s = s.parent
  until not s
  return x, y
end

function win:show()
  if self.hidden then return end
  local x, y = self:realpos()
  screen:offset(x, y)
  if self.w then
    screen:fill_rect(0, 0, self.w - 1, self.h - 1, self.bg)
    if self.border ~= false then
      screen:rect(0, 0, self.w - 1, self.h - 1, self.fg)
    end
    if self.title then
      local w, h = self.font:size(self.title)
      screen:fill(0, 0, self.w, h, self.fg)
      self.font:text(self.title, self.bg):blend(screen, (self.w - w)/2, 0)
    end
  end
  screen:nooffset()
  table.sort(self.childs, function(a, b) return a.lev < b.lev end)
  for _, w in ipairs(self.childs) do
    w:show()
  end
end

function win:mevent(r, mb, x, y)
  if not r:startswith 'mouse' or r == 'mousewheel' then
    return false
  end
  local xx, yy = self:realpos()
  x = x - xx
  y = y - yy
  if x >= 0 and x < self.w and y >= 0 and y < self.h then
    return r, mb, x, y
  end
  return false
end

function win:event(r, ...)
  if self.hidden then return end
  if not r then return end
  table.sort(self.childs, function(a, b) return a.lev < b.lev end)
  for _, w in ipairs(self.childs) do
    if w:event(r, ...) then return true end
  end
end

function win:for_childs(fn, ...)
  for _, v in ipairs(self.childs) do
    fn(v, ...)
  end
end
local stack = {
  { nam = 'synth' },
}

local w_conf

function push_box(s)
  if #stack == 8 then return end
  w_conf.hidden = true
  table.insert(stack, 1, { nam = s.text })
  build_stack()
end

function remove_box(s)
  w_conf.hidden = true
  table.remove(stack, s.id)
  build_stack()
end

local boxes = {
  { nam = 'synth',
    { 'type', synth.WAVE_TYPE },
    { 'width', synth.WAVE_WIDTH, def = 0.5 },
    { 'attack', synth.ATTACK_TIME, def = 0.01  },
    { 'decay', synth.DECAY_TIME, def = 0.1 },
    { 'sustain', synth.SUSTAIN_LEVEL, def = 0.5 },
    { 'release', synth.RELEASE_TIME, def = 0.3 },
  },
  { nam = 'dist',
    { "volume", synth.VOLUME },
    { "gain", synth.gain },
  },
  { nam = 'delay',
    { 'volume', synth.VOLUME },
    { 'time', synth.TIME, max = 1, min = 0 },
    { 'feedback', synth.FEEDBACK },
  },
  { nam = 'filter' },
}

w_conf = win:new { title = 'Settings',
    hidden = true,
    w = 32 * 7,
    h = 10 * 2,
    border = true }

function box_info(nam)
  for _, v in ipairs(boxes) do
    if v.nam == nam then return v end
  end
end

local w_stack = win:new { title = 'Stack',
  w = 16*7,
  border = true }

function config_box(s)
  if s.selected then
    s.selected = false
    w_conf.hidden = true
    return
  end
  s.parent:for_childs(function(w) w.selected = false end)
  s.selected = true
  local b = s.box
  w_conf.childs = {}
  local info = box_info(b.nam)
  for i, v in ipairs(info) do
    local wl = label:new { text = v[1], w = 16*7/2, h = 10, lev = -1 }
    wl.x = (w_conf.w/2 - wl.w)/2
    wl.y = i * 10 + 2
    local wb = edit:new { value = tostring(stack[s.id][v[1]] or v.def or 0),
      w = 16*7/2, h = 10, lev = -1 }
    wb.y = wl.y
    wb.id = s.id
    wb.nam = v[1]
    wb.par = v[2]
    wb.onedit = function(s)
      stack[s.id][s.nam] = s.value
      apply_change(#stack - s.id, s.par, tonumber(s.value) or 0)
    end
    wb.x = w_conf.w/2
    w_conf:with { wl, wb }
  end
  w_conf.h = (#info + 2) * 10 + 16
  w_conf.y = H - w_conf.h
  w_conf.x = w_stack.x + w_stack.w + 1
  w_conf.hidden = false
  local rem = button:new {
    text = 'Remove', w = 24 * 7, h = 10, lev = -1 }
  rem.x = (w_conf.w - rem.w)/2
  rem.y = w_conf.h - 12
  rem.id = s.id
  rem.onclick = remove_box
  w_conf:with { rem }
end

function apply_change(id, par, val)
  for c = 1, chans.max do
    synth.change(c, id, par, val)
  end
end

function apply_boxes()
  for c = 1, chans.max do
    chans[c] = false
    synth.free(c)
    for i=#stack,1,-1 do
      synth.push(c, stack[i].nam)
      local info = box_info(stack[i].nam)
      for _, v in ipairs(info) do
        local n, p = v[1], v[2]
        if stack[i][n] then
          synth.change(c, -1, p, stack[i][n])
        end
      end
    end
    synth.set(c, true, 1)
  end
end

function build_stack()
  w_stack.h = (#stack + 2)*10
  w_stack.x = 0
  w_stack.y = H - w_stack.h
  w_stack.childs = {}
  for i, b in ipairs(stack) do
    local wb = button:new { text = b.nam, w = 14*7, h = 10, lev = -1 }
    wb.x = (w_stack.w - wb.w)/2
    wb.y = i * 10 + 2
    wb.box = b
    wb.id = i
    wb.onclick = config_box
    w_stack:with { wb }
  end
  apply_boxes()
end

build_stack()

local w_boxes = win:new { title = 'Push box',
  w = 16*7, h = (#boxes + 2)* 10,
  border = true }

w_boxes.x = W - w_boxes.w
w_boxes.y = 0

for i, b in ipairs(boxes) do
  local wb = button:new { text = b.nam, w = 14*7, h = 10, lev = -1 }
  wb.x = (w_boxes.w - wb.w)/2
  wb.y = i * 10 + 2
  wb.onclick = push_box
  w_boxes:with { wb }
end

local w_play = button:new { w = 64, h = 12, x = 0, y = 0, text = "PLAY", border = true, lev = 2 }
local w_info = label:new { w = 29*7, h = 12, x = w_play.x + w_play.w + 2, text = "", border = false, left = true } 

local key2note = {
  z = 0, s = 1, x = 2, d = 3, c = 4, v = 5, g = 6, b = 7, h = 8, n = 9, j = 10, m = 11,
  [','] = 12, l = 13, ['.'] = 14, [';'] = 15, ['/'] = 16,
  q = 12, [2] = 13, w = 14, [3] = 15, e = 16, r = 17, [5] = 18, t = 19, [6] = 20, y = 21, [7] = 22, u = 23,
  i = 24, [9] = 25, o = 26, [0] = 27, p = 28, ['['] = 29, ['='] = 30, [']'] = 31,
}

local note2sym = { 'c-', 'c#', 'd-', 'd#', 'e-', 'f-', 'f#', 'g-', 'g#', 'a-', 'a#', 'b-' }

w_play.octave = 2

function w_info:show()
  if not w_play.play then
    self.text = ''
  else
    self.text = string.format('%d', w_play.octave)
    for i = 1, chans.max do
      if chans[i] then
        self.text = self.text .. ' '..chans.notes[i]
--      else
--        self.text = self.text .. ' ...'
      end
    end
  end
  label.show(self)
end

function w_play:onclick()
  self.play = not self.play
  self.selected = self.play
  if self.play then
    apply_boxes()
  else
    for i=1, chans.max do
      synth.free(i)
    end
  end
end

function find_free_channel()
  local free = {}
  for c = 1, chans.max do
    if not chans[c] then
      table.insert(free, c)
    end
  end
  if #free == 0 then return 1 end
  table.sort(free, function(a, b)
    return (chans.times[a] or 0) < (chans.times[b] or 0)
  end)
  return free[1]
end

function w_play:event(r, v, ...)
  if button.event(self, r, v, ...) then return true end
  if v ~= 'space' and not self.play then return end
  if r == 'keydown' then
    if v == 'space' then
      self:onclick()
      return true
    end
    if v:find("^f[1-5]$") then
      self.octave = tonumber(v:sub(2))
      return true
    end
    v = tonumber(v) or v
    local m = key2note[v]
    if not m then
      return
    end
    local note = note2sym[m%12 + 1]
    note = string.format("%s%d", note, w_play.octave + math.floor(m/12))
    m = m + 12 * (w_play.octave + 2)
    local hz = 440 * 2 ^ ((m - 69) / 12) -- sfx.get_note(m..'3')
    for c = 1, chans.max do
      if chans[c] == v then
        return true
      end
    end
    local c = find_free_channel()
    chans[c] = v
    chans.notes[c] = note
    chans.times[c] = sys.time()
    synth.change(c, 0, synth.NOTE_ON, hz)
    synth.change(c, 0, synth.VOLUME, 0.5)
    return true
  elseif r == 'keyup' then
    for c = 1, chans.max do
      v = tonumber(v) or v
      if chans[c] == v then
        chans[c] = false
        synth.change(c, 0, synth.NOTE_OFF, 0)
        break
      end
    end
  end
end

win:with { w_boxes, w_stack, w_conf, w_play, w_info }

while true do
  win:event(sys.input())
  win:show()
  if w_conf then
    w_conf.y = H - w_conf.h
    w_conf.x = w_stack.x + w_stack.w + 1
    w_conf:show()
  end
  gfx.flip(1/30, true)
end
