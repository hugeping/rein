local sfx = require 'sfx'
local editor = require 'editor'

local w_conf, w_rem, w_bypass, w_voice

gfx.win(384, 384)
mixer.volume(0.5)

local FILE = ARGS[2] or 'voices.syn'

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

function win:below(d)
  return self.y + self.h + (d or 0)
end

local editarea = win:new { value = '', hl = { 0, 0, 0, 32 } }

function editarea:new(w)
  w.childs = {}
  w.edit = editor.new()
  w.glyph_cache = {}
  setmetatable(w, self)
  self.__index = self
  w.spw, w.sph = w.font:size(" ")
  return w
end

function editarea:size(w, h)
  if not w then
    return self.edit:size()
  end
  self.w, self.h = w, h
  self.edit:size(math.floor(w / self.spw), math.floor(h / self.sph)-1)
end

function editarea:cursor(px, py)
  local s = self
  if math.floor(sys.time()*4) % 2 == 1 then
    return
  end
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

function editarea:glyph(t, x, y, sel)
  local key = t
  local g
  if not self.glyph_cache[key] then
    self.glyph_cache[key] = self.font:text(t, self.fg) or self.font:text("?", self.fg)
  end
  g = self.glyph_cache[key]
  if sel then
    screen:fill_rect(x, y, x + self.spw-1, y + self.sph-1, self.hl)
  end
  g:blend(screen, x, y)
end

function editarea:show()
  if self.hidden then return end
  win.show(self)
  local x, y = self:realpos()
  screen:offset(x + 1, self.title and (y + 10) or y)
  screen:clip(x, y, self.w, self.h)
  local px, py = 0, 0
  for nl, s, e in self.edit:visible_lines() do
    local l = self.edit.lines[nl]
    px = 0
    for i=s, e do
      self:glyph(l[i], px, py, self.edit:insel(i, nl))
      px = px + self.spw
    end
    py = py + self.sph
  end
  local cx, cy = self.edit:coord(self.edit:cursor())
  px, py = (cx - 1)*self.spw, (cy - 1)*self.sph
  self:cursor(px, py)
  screen:noclip()
  screen:nooffset()
end

function editarea:event(r, v, ...)
  if self.hidden then return end
  local m, mb, x, y = self:mevent(r, v, ...)
  if m and r == 'mousedown' and y >= 10 then
    y = math.floor((y - 10)/self.sph)
    x = math.floor(x/self.spw)
    self.edit:move(x + self.edit.col, y + self.edit.line)
    return true
  end
  if r == 'text' then
    self.edit:input(v)
    return true
  elseif r == 'keydown' then
    if v == 'backspace' then
      self.edit:backspace()
    elseif v == 'return' or v == 'keypad enter' then
      self.edit:newline()
    elseif v == 'up' then
      self.edit:move(false, self.edit.cur.y - 1)
    elseif v == 'down' then
      self.edit:move(false, self.edit.cur.y + 1)
    elseif v == 'right' then
      self.edit:move(self.edit.cur.x + 1)
    elseif v == 'left' then
      self.edit:move(self.edit.cur.x - 1)
    elseif v == 'home' or v == 'keypad 7' or
      (v == 'a' and input.keydown 'ctrl') then
      self.edit:move(1)
    elseif v == 'end' or v == 'keypad 1' or
      (v == 'e' and input.keydown 'ctrl') then
      self.edit:toend()
    elseif v == 'pagedown' or v == 'keypad 3' then
      local _, lines = self:size()
      self.edit:move(false, self.edit.cur.y + lines)
    elseif v == 'pageup' or v == 'keypad 9' then
      local _, lines = self:size()
      self.edit:move(false, self.edit.cur.y - lines)
    elseif v == 'y' and input.keydown 'ctrl' then
      self.edit:cutline()
    elseif v == 'c' and input.keydown 'ctrl' then
      self.edit:cut(true)
    elseif v == 'v' and input.keydown 'ctrl' then
      self.edit:paste()
--    elseif v == 'd' and input.keydown 'ctrl' then
--      if not w_conf.hidden then
--        w_conf.edit:set(sfx.box_defs(w_conf.nam))
--      end
    elseif v == 'x' and input.keydown 'ctrl' or v == 'delete' then
      if v == 'delete' and not self.edit:selection() then
        self.edit:delete()
      else
        self.edit:cut()
      end
    elseif v == 'z' and input.keydown 'ctrl' then
      self.edit:undo()
    elseif v:find 'shift' then
       self.edit:select(true)
    end
    self.edit:move()
    self.edit:select()
  elseif r == 'keyup' then
    if v:find 'shift' then
      self.edit:select(false)
    end
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
  local m, d = self:mevent(r, v, ...)
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
    if self.edit and self.onedit then self:onedit() end
    self.edit = not self.edit
    return true
  elseif m == 'mousewheel' and self.delta then
    self.value = (tonumber(self.value) or 0) - self.delta * d
    if self.min and self.value < self.min then self.value = self.min end
    if self.max and self.value > self.max then self.value = self.max end
    self.value = tostring(self.value)
  end
end

function win:fmt(s)
  return s
end

function edit:show()
  win.show(self)
  local w, h = self.font:size(self:fmt(self.value) .. (self.edit and '|' or ''))
  local x, y = self:realpos()
  screen:offset(x, y)
  if not tostring(self.value):empty() or self.edit then
    screen:clip(x, y, self.w, self.h)
    local xoff = (self.w - w)/2
    if xoff < 0 then xoff = self.w - w end
    self.font:text(self:fmt(self.value) ..
      (self.edit and '|' or ''), self.fg):
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
  if self.hidden then return end
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
  if r == 'mousewheel' then x, y = input.mouse() end
  if not r:startswith 'mouse' then
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

function conf_show(show)
  w_conf.hidden = not show
  w_rem.hidden = not show
  w_bypass.hidden = not show
  w_bypass.selected = show and stack[w_conf.id].bypass
end

function push_box(s)
  if not config_check() then
    return
  end
  if #stack == 8 then return end
  conf_show(false)
  table.insert(stack, 1, { nam = s.text })
  build_stack()
end

function remove_box(s)
  conf_show(false)
  table.remove(stack, s.id)
  build_stack()
end

w_conf = editarea:new { title = 'Settings',
    hidden = true,
    y = 13,
    border = true }
w_conf:size(38 * 7 + 5, H - 13 - 20 + 7)

w_rem = button:new { hidden = true, text = 'Remove',
  w = 8 * 7, h = 12, lev = -1, y = H - 12, x = H - 8*7, border = true,
  onclick = remove_box }

w_bypass = button:new { hidden = true, text = 'Bypass',
  w = 8 * 7, h = 12, lev = -1, y = H - 12, x = H - 8*7 - 8*7 - 1, border = true,
  onclick = bypass_box }

local w_file = button:new { text = FILE, w = 22*7, bg = 7,
  h = 12, y = H - 12, x = 113 }

function dirty(flag)
  if flag then
    w_file.bg = 8
  else
    w_file.bg = 7
  end
end

function w_bypass:onclick()
  stack[w_conf.id].bypass = not stack[w_conf.id].bypass
  self.selected = stack[w_conf.id].bypass
  build_stack()
  conf_show(true)
end

function w_file:onclick()
  if not config_check() then
    return
  end
  if save(FILE) then dirty(false) end
end

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
  for _, l in ipairs(w_conf.edit.lines) do
    if l[1] ~= '#' or l[2] ~= 'e' or l[3] ~= 'r' or l[4] ~= 'r' or l[5] ~= ' ' then
      table.insert(lines, l)
    end
  end
  w_conf.edit.lines = lines

  local r, e, line = sfx.compile_box(w_conf.nam, w_conf.edit:get())
  if r then
    if stack[w_conf.id].conf ~= w_conf.edit:get() then
      dirty(true)
    end
    stack[w_conf.id].conf = w_conf.edit:get()
    return true
  end
  w_conf.edit:move(#w_conf.edit.lines[line] + 1, line)
  local width = w_conf.edit:size()
  for l in e:lines() do
    for _, ll in ipairs(l:wrap(width-2)) do
      w_conf.edit:newline()
      w_conf.edit:input('#err '..ll)
    end
  end
  w_conf.edit.col = 1
  w_conf.edit:move(#w_conf.edit.lines[line] + 1, line)
  return false, e, line
end

function config_box(s)
  if not config_check() then
    return
  end
  if s.selected then
    s.selected = false
    conf_show(false)
    return
  end
  s.parent:for_childs(function(w) w.selected = false end)
  s.selected = true
  local b = s.box
  w_conf.id = s.id
  w_conf.nam = b.nam
  local text = stack[s.id].conf
  w_conf.edit:set(text or sfx.box_defs(b.nam))
  w_conf.x = w_stack.x + w_stack.w + 1
  w_conf.edit:move(1, 1)
  conf_show(true)
  w_rem.id = s.id
end

function apply_boxes()
  for c = 1, chans.max do
    chans[c] = false
    synth.drop(c)
    for i=#stack,1,-1 do
      synth.push(c, stack[i].bypass and "bypass" or stack[i].nam)
      local conf, e = sfx.compile_box(stack[i].nam,
        stack[i].conf or sfx.box_defs(stack[i].nam))
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
  w_rem.hidden = true
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
  w_voice.value = voices[cur_voice].nam
  apply_boxes()
end

function save(fname)
  local txt = ''
  for _, v in ipairs(voices) do
    txt = txt .. string.format("voice %s\n", v.nam:gsub(" ", "_"))
    local conf = ''
    for _, b in ipairs(v) do
      conf = string.format("box %s\n%s", b.nam, b.conf or sfx.box_defs(b.nam)) .. conf
    end
    txt = txt .. conf:strip() .. '\n\n'
  end
  print(txt:strip())
  return io.file(fname, txt:strip()..'\n')
end


local w_boxes = win:new { title = 'Push box',
  w = 16*7, h = (#sfx.boxes + 2)* 10,
  border = true }

local w_volume = win:new { title = 'Mix vol.',
  lev = -3,
  w = 16*7, h = 22, x = 0, y = w_boxes:below(16),
  border = true }:with {
  edit:new { border = false, value = 0.5, x = 1, y = 10, w = 16*7-2, h = 10,
    delta = 0.01, min = 0,
    onedit = function(s)
      s.value = tonumber(s.value) or 0.5
      mixer.volume(s.value)
    end
  }
}

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

w_voice = edit:new { border = false, value = voices[cur_voice].nam,
  x = w_prev:after(1), y = 0, w = 14*7-8, h = 12, lev = -2.1,
  fmt = function(s, str)
    if s.edit then return str end
    if cur_voice == tonumber(str) then
      return string.format("%d", cur_voice)
    end
    return string.format("%d:%s", cur_voice, str)
  end,
  onedit = function(s)
    for k, v in ipairs(voices) do
      if v.nam == s.value or k == tonumber(s.value) then
        cur_voice = k
        stack = voices[cur_voice]
        build_stack()
        return
      end
    end
    if s.value:empty() then s.value = tostring(cur_voice) end
    voices[cur_voice].nam = s.value
  end
}

local w_next = button:new { text = ">",
  x = w_voice:after(1),
  y = 0, w = 10, h = 12, border = true }

function w_prev:onclick(s)
  if not config_check() then
    return
  end
  cur_voice = cur_voice - 1
  if cur_voice < 1 then cur_voice = 1 end
  stack = voices[cur_voice]
  build_stack()
end

function w_next:onclick(s)
  if not config_check() then
    return
  end
  cur_voice = cur_voice + 1
  if not voices[cur_voice] then
    voices[cur_voice] = { nam = tostring(cur_voice) }
  end
  stack = voices[cur_voice]
  build_stack()
end

function load(fname)
  local v, e
  v, e = io.file(fname)
  if not v then
    return v, e
  end
  v, e = sfx.parse_voices(v)
  if not v then
    return v, e
  end
  voices = {}
  for _, voice in ipairs(v) do
    local vo = { nam = voice.nam }
    table.insert(voices, vo)
    for _, b in ipairs(voice) do
      table.insert(vo, 1, { nam = b.nam, conf = b.conf })
    end
  end
  cur_voice = 1
  stack = voices[cur_voice]
  w_voice.value = voices[cur_voice].nam
  build_stack()
  return true
end

local w_play = button:new { w = 5*7, h = 12,
  x = W - 5*7, y = 0, text = "PLAY", border = true, lev = -2 }
local w_poly = button:new { w = 5*7, h = 12,
  x = W - 10*7 - 1, y = 0, text = "POLY", border = true, lev = -2, selected = true }
local w_info = label:new { w = 28*7, h = 12,
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

function w_poly:onclick()
  self.selected = not self.selected
  if not self.selected then
    chans.max = 1
  else
    chans.max = 10
  end
end

function w_play:onclick()
  if not config_check() then
    return
  end
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

local play_stop_keys = {
  backspace = true;
  left = true;
  right = true;
  down = true;
  up = true;
}
function w_play:event(r, v, ...)
  if self.selected and not w_conf.hidden and
    ((w_conf:mevent(r, v, ...) and r == 'mousedown') or
    (r == 'keydown' and play_stop_keys[v]))
    and self.selected then
    self:onclick()
    return
  end

  if button.event(self, r, v, ...) then return true end
  if v ~= 'escape' and not self.play then return end
  if r == 'text' then
    return true
  elseif r == 'keydown' then
    if v == 'escape' then
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

win:with { w_prev, w_voice, w_next, w_boxes, w_volume, w_stack, w_conf, w_play,
  w_poly, w_info, w_rem, w_bypass, w_file }

local r, e = load(FILE)
if not r then
  print("Error loading voices: ".. tostring(e))
end

build_stack()

while true do
  win:event(sys.input())
  win:show()
  gfx.flip(1/20, true)
end
