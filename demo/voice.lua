local sfx = require 'sfx'
gfx.win(384, 384)
mixer.volume(0.5)

local cur_voice = 1

local chans = { notes = {}, times = {}, max = 10 } -- number of fingers :)

local W, H = screen:size()

local win = {
  padding = 1.2,
  border = false,
  x = 0, y = 0,
  w = W, h = H,
  fg = 0, bg = 16,
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

function win:after(d)
  return self.x + self.w + (d or 0)
end

local editarea = win:new { value = '', cur = {x = 1, y = 1},
  col = 1, line = 1, lines = {}, sph = 10, spw = 7, glyph_cache = {} }

function editarea:set(text)
  self.lines = {}
  for l in text:lines() do
    table.insert(self.lines, utf.chars(l))
  end
end

function editarea:get()
  local text = ''
  for _, l in ipairs(self.lines) do
    text = text .. table.concat(l) .. '\n'
  end
  return text
end

function editarea:scroll()
  local s = self
  if s.cur.x < 1 then s.cur.x = 1 end
  if s.cur.y < 1 then s.cur.y = 1 end
  if s.cur.y > #s.lines then
    s.cur.y = #s.lines
    if #s.lines[s.cur.y] ~= 0 then
      s.cur.y = s.cur.y + 1
      s.cur.x = 1
      s.lines[s.cur.y] = {}
    end
  end
  if s.cur.x > #s.lines[s.cur.y] then s.cur.x = #s.lines[s.cur.y] + 1 end
  local columns = math.floor((s.w-2) / s.spw)
  local lines = math.floor(s.h / s.sph) - 2
  if s.cur.y >= s.line and s.cur.y <= s.line + lines - 1
    and s.cur.x >= s.col and s.cur.x < columns then
    return
  end
  if s.cur.x < s.col then
    s.col = s.cur.x
  elseif s.cur.x > s.col + columns - 1 then
    s.col = s.cur.x - columns + 1
  end
  if s.cur.y < s.line then
    s.line = s.cur.y
  elseif s.cur.y > s.line + lines - 1 then
    s.line = s.cur.y - lines + 1
  end
end

function editarea:input(t)
  local s = self
  local c = utf.chars(t)
  for _, v in ipairs(c) do
    table.insert(s.lines[s.cur.y], s.cur.x, v)
    s.cur.x = s.cur.x + 1
  end
  s:scroll()
end

function editarea:cursor()
  local s = self
  if math.floor(sys.time()*4) % 2 == 1 then
    return
  end
  local px, py = (s.cur.x - s.col)*s.spw, (s.cur.y - s.line)*s.sph
  for y=py, py + s.sph-1 do
    for x=px, px + s.spw-1 do
      local r, g, b = screen:pixel(x, y)
      r = bit.bxor(r, 255)
      g = bit.bxor(g, 255)
      b = bit.bxor(b, 255)
      screen:pixel(x, y, {r, g, b, 255})
    end
  end
end

function editarea:glyph(t)
  local key = t
  if self.glyph_cache[key] then
    return self.glyph_cache[key]
  end
  self.glyph_cache[key] = self.font:text(t, self.fg)
  return self.glyph_cache[key]
end

function editarea:show()
  if self.hidden then return end
  win.show(self)
  local x, y = self:realpos()
  screen:offset(x + 1, self.title and (y + 10) or y)
  screen:clip(x, y, self.w, self.h)
  local px, py, l
  py = 0
  for nr=self.line, #self.lines do
    l = self.lines[nr]
    px = 0
    for i=self.col,#l do
      if px >= self.w then
        break
      end
      local g = self:glyph(l[i]) or glyph("?")
      local w, _ = g:size()
      g:blend(screen, px, py)
      px = px + w
    end
    py = py + self.sph
    if py >= self.h - 12 then
      break
    end
  end
  self:cursor()
  screen:noclip()
  screen:nooffset()
end

function editarea:newline()
  local s = self
  local l = s.lines[s.cur.y]
  table.insert(s.lines, s.cur.y + 1, {})
  for k=s.cur.x, #l do
    table.insert(s.lines[s.cur.y+1], table.remove(l, s.cur.x))
  end
  s.cur.y = s.cur.y + 1
  s.cur.x = 1
end

function editarea:backspace()
  local s = self
  if s.cur.x > 1 then
    table.remove(s.lines[s.cur.y], s.cur.x - 1)
    s.cur.x = s.cur.x - 1
  elseif s.cur.y > 1 then
    local l = table.remove(s.lines, s.cur.y)
    s.cur.y = s.cur.y - 1
    s.cur.x = #s.lines[s.cur.y] + 1
    for _, v in ipairs(l) do
      table.insert(s.lines[s.cur.y], v)
    end
  end
end

function editarea:event(r, v, ...)
  if self.hidden then return end
  local m, mb, x, y = self:mevent(r, v, ...)
  if m and r == 'mousedown' and y >= 10 then
    y = math.floor((y - 10)/self.sph)
    x = math.floor(x/self.spw)
    self.cur.y = y + self.line
    self.cur.x = x + self.col
    self:scroll()
    return true
  end
  if r == 'text' then
    self:input(v)
    return true
  elseif r == 'keydown' then
    if v == 'backspace' then
      self:backspace()
    elseif v == 'return' or v == 'keypad enter' then
      self:newline()
    elseif v == 'up' then
      self.cur.y = self.cur.y - 1
    elseif v == 'down' then
      self.cur.y = self.cur.y + 1
    elseif v == 'right' then
      self.cur.x = self.cur.x + 1
    elseif v == 'left' then
      self.cur.x = self.cur.x - 1
    elseif v == 'home' or v == 'keypad 7' or
      (v == 'a' and input.keydown 'ctrl') then
      self.cur.x = 1
    elseif v == 'end' or v == 'keypad 1' or
      (v == 'e' and input.keydown 'ctrl') then
      self.cur.x = #self.lines[self.cur.y] + 1
    end
    self:scroll()
  end
  return win.event(self, r, v, ...)
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
      if self.edit and self.onedit then self:onedit() end
      self.edit = false
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
  if not tostring(self.value):empty() or self.edit then
    screen:clip(x, y, self.w, self.h)
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
  screen:clip(x, y, self.w, self.h)
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

local voices = {
  { nam = '1', { nam = 'synth' } },
}

local stack = voices[cur_voice]

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

w_conf = editarea:new { title = 'Settings',
    hidden = true,
    w = 38 * 7,
    h = 10 * 2,
    border = true }

function box_info(nam)
  for _, v in ipairs(sfx.boxes) do
    if v.nam == nam then return v end
  end
end

local w_stack = win:new { title = 'Stack',
  w = 16*7,
  border = true }

function config_check()
  if w_conf.hidden then
    return true
  end
  local lines = {}
  for _, l in ipairs(w_conf.lines) do
    if l[1] ~= '#' or l[2] ~= 'e' or l[3] ~= 'r' or l[4] ~= 'r' or l[5] ~= ' ' then
      table.insert(lines, l)
    end
  end
  w_conf.lines = lines

  local r, e, line = sfx.compile(w_conf.nam, w_conf:get())
  if r then
    stack[w_conf.id].conf = w_conf:get()
    return true
  end
  w_conf.cur.y = line
  w_conf.cur.x = #w_conf.lines[line] + 1
  for l in e:lines() do
    w_conf:newline()
    w_conf:input('#err '..l)
  end
  w_conf.cur.y = line
  w_conf.cur.x = #w_conf.lines[line] + 1
  w_conf.col = 1
  w_conf:scroll()
  return false, e, line
end

function config_box(s)
  if not config_check() then
    return
  end
  if s.selected then
    s.selected = false
    w_conf.hidden = true
    return
  end
  s.parent:for_childs(function(w) w.selected = false end)
  s.selected = true
  local b = s.box
  w_conf.id = s.id
  w_conf.nam = b.nam
  w_conf.childs = {}
  local text = stack[s.id].conf
  w_conf:set(text or sfx.defs(b.nam))
  w_conf.h = H - 13
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

function apply_boxes()
  for c = 1, chans.max do
    chans[c] = false
    synth.drop(c)
    for i=#stack,1,-1 do
      synth.push(c, stack[i].nam)
      local conf, e = sfx.compile(stack[i].nam, stack[i].conf or '')
      if not conf then
        error("Error compiling box: "..e)
      end
      for _, args in ipairs(conf) do
        synth.change(c, -1, table.unpack(args))
      end
    end
    synth.on(c, true)
    synth.vol(c, 1)
  end
end

function build_stack()
  w_stack:for_childs(function(w) w.selected = false end)
  w_conf.hidden = true
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
  w = 16*7, h = (#sfx.boxes + 2)* 10,
  border = true }

w_boxes.x = 0 -- W - w_boxes.w
w_boxes.y = 12 + 1

for i, b in ipairs(sfx.boxes) do
  local wb = button:new { text = b.nam, w = 14*7, h = 10, lev = -1 }
  wb.x = (w_boxes.w - wb.w)/2
  wb.y = i * 10 + 2
  wb.onclick = push_box
  w_boxes:with { wb }
end

local w_prev = button:new { text = "<" ,
  x = 0, y = 0, w = 10, h = 12, border = true}

local w_voice = edit:new { border = false, value = voices[cur_voice].nam,
  x = w_prev:after(1), y = 0, w = 14*7-8, h = 12,
  onedit = function(s)
    if s.value:empty() then s.value = tostring(cur_voice) end
    voices[cur_voice].nam = s.value
  end
}

local w_next = button:new { text = ">",
  x = w_voice:after(1),
  y = 0, w = 10, h = 12, border = true }

function w_prev:onclick(s)
  cur_voice = cur_voice - 1
  if cur_voice < 1 then cur_voice = 1 end
  stack = voices[cur_voice]
  w_voice.value = voices[cur_voice].nam
  build_stack()
end

function w_next:onclick(s)
  cur_voice = cur_voice + 1
  if not voices[cur_voice] then
    voices[cur_voice] = { nam = tostring(cur_voice) }
  end
  stack = voices[cur_voice]
  w_voice.value = voices[cur_voice].nam
  build_stack()
end

local w_play = button:new { w = 64, h = 12,
  x = W - 64, y = 0, text = "PLAY", border = true, lev = -2 }
local w_info = label:new { w = 29*7, h = 12,
  x = w_next:after(1), y = w_play.y, text = "", border = false, left = true }

local key2note = {
  z = 0, s = 1, x = 2, d = 3, c = 4, v = 5, g = 6, b = 7, h = 8, n = 9, j = 10, m = 11,
  [','] = 12, l = 13, ['.'] = 14, [';'] = 15, ['/'] = 16,
  q = 12, [2] = 13, w = 14, [3] = 15, e = 16, r = 17, [5] = 18, t = 19, [6] = 20, y = 21, [7] = 22, u = 23,
  i = 24, [9] = 25, o = 26, [0] = 27, p = 28, ['['] = 29, ['='] = 30, [']'] = 31,
}

local note2sym = { 'c-', 'c#', 'd-', 'd#', 'e-', 'f-', 'f#', 'g-', 'g#', 'a-', 'a#', 'b-' }

w_play.octave = 2

function apply_change(id, par, val)
  if not w_play.play then
    return
  end
  for c = 1, chans.max do
    synth.change(c, id, par, val)
  end
end

function w_info:show()
  if not w_play.play then
    self.text = ''
    self.bg = nil
  else
    self.text = string.format('%d', w_play.octave)
    for i = 1, chans.max do
      if chans[i] then
        self.text = self.text .. ' '..chans.notes[i]
--      else
--        self.text = self.text .. ' ...'
      end
    end
    self.bg = 15
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
      synth.drop(i)
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
  if v ~= 'escape' and not self.play then return end
  if r == 'text' then
    return true
  elseif r == 'keydown' then
    if v == 'escape' then
      if not config_check() then
        return true
      end
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
      return true
    end
    if #stack == 0 then return true end
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
--    synth.change(c, 0, synth.VOLUME, 0.5)
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

win:with { w_prev, w_voice, w_next, w_boxes, w_stack, w_conf, w_play, w_info }

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
