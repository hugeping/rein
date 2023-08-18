local editor = require "editor"

local sfont = font

local idle_mode
local inp_mode
local help_mode
local b, inp

local conf = {
  fg = 0,
  bg = 16,
  scalable = false,
  scalable_font = DATADIR..'/iosevka.ttf',
  scalable_font_sz = 14,
  cursor_blink = true,
  brd = { 0xde, 0xde, 0xde },
  hl = { 0, 0, 0, 32 },
  status = { 0, 0, 0, 64 },
  keyword = 8,
  string = 14,
  number = 12,
  comment = 6,
  bracket = 3,
  math = 3,
  delim = 4,
  syntax = true,
}

if conf.scalable then
  sys.event_filter().resized = true
  local w, h = sys.window_size()
  gfx.win(w, h)
  local fn = DATADIR..'/iosevka.ttf'
  local sz = conf.scalable_font_sz * SCALE
  if conf.scalable_font then
    sfont = gfx.font(fn, sz)
    font = sfont
  end
  gfx.win(w - conf.scalable_font_sz, h - conf.scalable_font_sz, fn, sz)
else
  sys.event_filter().resized = false
  gfx.win(385, 380)
end

local W, H = screen:size()

gfx.border(conf.brd)

local FILE = ARGS[2] or 'main.lua'

local buff = {
}
buff.__index = buff

local glyph_cache = { col = { } }

local function clone(t)
  local l = {}
  for _, v in ipairs(t) do
    table.insert(l, v)
  end
  return l
end

function glyph(t, col)
  col = col or conf.fg
  glyph_cache[col] = glyph_cache[col] or {}
  if glyph_cache[col][t] then
    return glyph_cache[col][t]
  end
  glyph_cache[col][t] = sfont:text(t, col)
  return glyph_cache[col][t]
end

function buff:resize(w, h)
  local b = self
  b.spw, b.sph = sfont:size(" ")
  b.w, b.h = w, h
  b.columns = math.floor(b.w / b.spw)
  b.lines = math.floor(b.h / b.sph)
  b.edit:size(b.columns, b.lines)
end

function buff.new(fname, x, y, w, h)
  local b = { edit = editor.new(), fname = fname,
    x = x or 0, y = y or 0, w = w or W, h = h or H }
  local f = fname and io.open(fname, "rb")
  if f then
    for l in f:lines() do
      l = l:gsub("\t", "  ")
      table.insert(b.edit.lines, utf.chars(l))
    end
    f:close()
  end
  setmetatable(b, buff)
  b:resize(b.w, b.h)
  return b
end

function buff:lookuptag(tag)
  local s = self
  local insect
  local y1, y2
  for k, l in ipairs(s.edit.lines) do
    local str = table.concat(l, '')
    if insect then
      if str:find("]]") then
        y2 = k
        break
      end
    elseif str:find("^[ \t]*local[ \t]+"..tag.."[ \t=]") then
      insect = true
      y1 = k
    end
  end
  if not y1 or not y2 then
    return
  end
  return y1, y2
end

function buff:export(tag, fname)
  local s = self
  local y1, y2 = s:lookuptag(tag)
  if not y1 then
    return false, "No data"
  end
  local f, e = io.open(fname, "wb")
  local lines = 0
  if not f then
    return false, e
  end
  for y=y1, y2 do
    local str = table.concat(s.edit.lines[y], ""):gsub("%]%]$", ""):gsub("^.[^%[]*%[%[", "")
    if (y~=y1 and y~=y2) or not str:empty() then
      f:write(str..'\n')
      lines = lines + 1
    end
  end
  f:close()
  print(string.format("%s: exported %d line(s)", fname, lines))
  return true
end

function buff:import(tag, fname)
  local s = self
  local y1, y2 = s:lookuptag(tag)
  if not y1 then
    y1, y2 = 1, 0
  end
  local f, e = io.open(fname, "r")
  local lines = 0
  if not f then
    return false, e
  end
  for y=y1, y2 do
    table.remove(s.edit.lines, y1)
  end
  table.insert(s.edit.lines, y1, utf.chars(string.format("local %s = [[", tag)))
  for l in f:lines() do
    lines = lines + 1
    table.insert(s.edit.lines, y1 + lines, utf.chars(l))
  end
  table.insert(s.edit.lines, y1 + lines + 1, utf.chars "]]")
  f:close()
  print(string.format("%s: imported %d line(s) at line %d", fname, lines, y1))
  return true
end

function buff:write()
  local s = self
  if type(s.fname) ~= 'string' then
    return
  end
  local f = io.open(s.fname, "wb")
  if not f then -- can open
    s.edit.dirty = true
    return
  end
  local eof = #s.edit.lines
  for k=#s.edit.lines,1,-1 do
    if #s.edit.lines[k] ~= 0 then
      eof = k
      break
    end
  end
  for k, l in ipairs(s.edit.lines) do
    l = table.concat(l, ''):gsub("[ \t]+$", "") -- strip
    f:write(l.."\n")
    if k == eof then
      break
    end
  end
  f:close()
  s.edit.dirty = false
  print(string.format("%s written", s.fname))
  return true
end

function buff:cursor()
  local s = self
  if conf.cursor_blink and math.floor(sys.time()*4) % 2 == 1 then
    return
  end
  local px, py = s.edit:coord(s.edit:cursor())
  px, py = (px - 1)*s.spw, (py - 1) * s.sph
  for y=py, py + s.sph-1 do
    for x=px, px + s.spw-1 do
      local r, g, b = screen:val(s.x + x, s.y + y)
      if r then
        r = bit.bxor(r, 255)
        g = bit.bxor(g, 255)
        b = bit.bxor(b, 255)
        screen:val(s.x + x, s.y + y, {r, g, b, 255})
      end
    end
  end
end

local function trimr(s, len)
  if utf.len(s) <= len then return s end
  local t = utf.chars(s)
  local r = '...'
  for i=#t-len+4, #t do
    r = r .. t[i]
  end
  return r
end

function buff:status()
  local s = self
  local cx, cy = self.edit:cursor()
  local fn = trimr(s.fname, 40)
  local info = string.format("%s%s %2d:%-2d %s%s",
    s.edit.dirty and '*' or '', fn, cx, cy,
    s.edit:insmode() and '+i' or ' ',
    s.edit:selmode() and '+v' or ' ')
  screen:clear(0, H - s.sph, W, H, conf.bg)
  screen:fill_rect(0, H - s.sph, W, H, conf.status)
  sfont:text(info, conf.fg):blend(screen, 0, H - s.sph)
end

function buff:selected()
  return self.edit:selected()
end

local kwd = {
  ["and"] = conf.keyword,
  ["in"] = conf.keyword,
  ["or"] = conf.keyword,
  ["repeat"] = conf.keyword,
  ["until"] = conf.keyword,
  ["for"] = conf.keyword,
  ["if"] = conf.keyword,
  ["do"] = conf.keyword,
  ["end"] = conf.keyword,
  ["while"] = conf.keyword,
  ["true"] = conf.keyword,
  ["false"] = conf.keyword,
  ["return"] = conf.keyword,
  ["then"] = conf.keyword,
  ["else"] = conf.keyword,
  ["elseif"] = conf.keyword,
  ["local"] = conf.keyword,
  ["require"] = conf.keyword,
  ["function"] = conf.keyword,
  ["break"] = conf.keyword,
}

local delim = {
  [" "] = conf.delim,
  ["/"] = conf.math,
  ["%"] = conf.math,
  ["+"] = conf.math,
  ["-"] = conf.math,
  ["*"] = conf.math,
  ["^"] = conf.math,
  ["#"] = conf.delim,
  ["."] = conf.delim,
  [","] = conf.delim,
  [";"] = conf.delim,
  ["("] = conf.bracket,
  [")"] = conf.bracket,
  ["{"] = conf.bracket,
  ["}"] = conf.bracket,
  ["["] = conf.bracket,
  ["]"] = conf.bracket,
  ["<"] = conf.math,
  [">"] = conf.math,
  ["'"] = conf.delim,
  ['"'] = conf.delim,
}

function buff:colorize_md(l, nl)
  local function prev_tag(indent)
    local l
    for i=nl-1, 1, -1 do
      l = self.edit.lines[i]
      if not l then return end
      local pos = false
      for k=1,#l do
        if l[k] ~= ' ' then
          pos = k
          break
        end
      end
      if not pos or pos > indent then return end
      for k=1,indent do
        if l[k] and l[k] ~= ' ' and k < indent then
          return l[k]
        end
      end
    end
  end
  local cols = {}
  local col
  for k=1, #l do
    local c = l[k]
    local pc = prev_tag(k)
    c = pc or c
    if not col then
      if c == '#' then
        col = conf.keyword
      elseif c == '-' or c == '*' then
        col = conf.string
      elseif c ~= ' ' then
        col = conf.fg
      end
    end
    cols[k] = col or conf.fg
  end
  return cols
end

local function colorstr(l, cols)
  local k, c, beg
  k = 1
  while k<=#l do -- strings
    while l[k] == '\\' do
      if beg then
        cols[k] = conf.string
        cols[k+1] = conf.string
      end
      k = k + 2
    end
    c = l[k]
    if not c then break end
    if not beg then
      if c == '-' and l[k+1] == '-' and #l < 128 then
        for i=k, #l do cols[i] = conf.comment end
        break
      end
      if c == '"' or c == "'" then
        beg = c
        cols[k] = conf.string
      end
    else
      cols[k] = conf.string
      if c == beg then
        beg = false
      end
    end
    k = k + 1
  end
end

function buff:colorize(l, nl)
  if not conf.syntax then
    return {}
  end
  if self.fname and self.fname:find("%.[mM][dD]$") then
    return self:colorize_md(l, nl)
  end
  local pre = ' '
  local start
  local key
  local cols = {}

  colorstr(l, cols)

  for k, c in ipairs(l) do
    if delim[pre] and not delim[c] and
        not cols[k] then
      key = ''
      start = k
    end
    if start then
      if not l[k+1] or delim[c] then
        key = key .. (delim[c] and '' or c)
        local col = kwd[key] or (tonumber(key) and key:len()<12 and conf.number)
        if col then
          for i=start,k do cols[i] = col end
        end
        if delim[c] then cols[k] = nil end
        start = false
      else
        key = key .. c
      end
    end
    if not cols[k] and delim[c] then
      cols[k] = (c == " " and 0) or delim[c]
    end
    pre = c
  end
  if not cols[1] and l[1] ~= ' ' then -- hack for multiline
    return {}
  end
  return cols
end

function buff:show()
  screen:clear(self.x, self.y, self.w, self.h, conf.bg)
  screen:clip(self.x, self.y, self.w, self.h)

  local px, py = 0, 0
  local cols, g
  for nl, s, e in self.edit:visible_lines() do
    local l = self.edit.lines[nl]
    px = 0
    cols = self:colorize(l, nl)
    for i=s, e do
      g = glyph(l[i], cols[i]) or glyph('?', cols[i])
      if self.edit:insel(i, nl) then
        screen:fill_rect(self.x + px, self.y + py,
          self.x + px + self.spw - 1,
          self.y + py + self.sph - 1, conf.hl)
      end
      g:blend(screen, self.x + px, self.y + py)
      px = px + self.spw
    end
    py = py + self.sph
  end
  self:cursor()
  screen:noclip()
  if self.status then
    self:status()
  end
end

function buff:jump(nr)
  local s = self
  s.edit:unselect()
  s.edit:move(false, nr)
end

function buff:keyup(k)
  local s = self
  if k:find 'shift' then
    s.edit:select(false)
  end
end

function buff:exec(prog, ...)
  mixer.init()
  gfx.win(256, 256)
  screen:clear(conf.bg)
  sys.input(true)
  sys.exec(prog, ...)
  sys.suspend()
end

function buff:readsel(fname)
  local s = self
  local w = io.file(fname)
  if w then
    s.edit:cut(false, false)
    s.edit:paste(w)
  end
end

function buff:writesel(fname)
  local s = self
  local clip = s.edit:cut(true, false)
  io.file(fname, clip)
end

function buff:mouse(r, v)
  local s = self
  local mx, my, mb = input.mouse()
  if mx < s.x or my < s.y or mx >= s.x + s.w or
    my >= s.y + s.h then
    return
  end
  local cx, cy = math.floor((mx - s.x)/s.spw),
    math.floor((my - s.y)/s.sph)
  if mb.left then
    s.edit:move(cx + s.edit.col,
      cy + s.edit.line)
  end
  if s.edit:selstarted() then
    s.edit:selmode(input.keydown 'alt')
  end
  if r == 'mousedown' then
    s.edit:select(true)
  elseif r == 'mouseup' then
    s.edit:select(false)
  elseif r == 'mousemotion' and mb.left then
    s.edit:select()
  elseif r == 'mousewheel' then
    local _, y = s.edit:cursor()
    s.edit:move(false, y - v*1)
  end
end

function buff:keydown(k)
  local s = self
  local cx, cy = s.edit:cursor()
  if s.edit:selstarted() then
    s.edit:selmode(input.keydown 'alt')
  end
  if k:find 'shift' then
    s.edit:select(true)
  elseif k == 'up' then
    if inp_mode then
      s:hprev()
    else
      s.edit:move(false, cy - 1)
    end
  elseif k == 'down' then
    if inp_mode then
      s:hnext()
    else
      s.edit:move(false, cy + 1)
    end
  elseif k == 'right' then
    s.edit:right()
  elseif k == 'left' then
    s.edit:left()
  elseif k == 'home' or k == 'keypad 7' or
    (k == 'a' and input.keydown 'ctrl') then
    s.edit:move(1)
  elseif k == 'end' or k == 'keypad 1' or
    (k == 'e' and input.keydown 'ctrl') then
    s.edit:move(#s.edit.lines[cy] + 1)
  elseif k == 'pagedown' or k == 'keypad 3' then
    s.edit:move(false, cy + s.lines)
  elseif k == 'pageup' or k == 'keypad 9' then
    s.edit:move(false, cy - s.lines)
  elseif k == 'return' or k == 'keypad enter' then
    s.edit:newline(true)
  elseif k == 'w' and input.keydown 'alt' then
    s.edit:wrap()
  elseif k == 'w' and input.keydown 'ctrl' then
    s.edit:selpar()
    return
  elseif k == 'backspace' then
    s.edit:backspace()
  elseif k == 'tab' then
    s.edit:input("  ")
  elseif k== 'f2' and input.keydown'shift' then
    inp_mode = not inp_mode
    if inp_mode then
      s.edit:select(false)
      inp_mode = 'write'
      inp.edit:set(FILE)
      inp.edit:move(128)
    end
  elseif k == 'f2' or (k == 's' and input.keydown'ctrl') then
    s:write()
  elseif k == 'f8' then
    os.remove('data.spr')
    os.remove('data.map')
    if not s:selected() then
      s:export ('__map__', 'data.map')
      s:export ('__spr__', 'data.spr')
    else
      s:writesel('data.spr')
    end
    idle_mode = 'spr'
    s:exec("sprited", 'data.spr')
  elseif k == 'f9' then
    os.remove('data.syn')
    os.remove('data.sng')
    if not s:selected() then
      s:export ('__voices__', 'data.syn')
      s:export ('__songs__', 'data.sng')
    else
      s:writesel('data.syn')
    end
    idle_mode = 'voices'
    s:exec("voiced", 'data.syn', 'data.sng')
  elseif k == 'f5' then
    s:write()
    idle_mode = 'run'
    s:exec(FILE)
  elseif k == 'escape' and inp_mode then
    inp_mode = false
  elseif k == 'insert' or k == 'keypad 0' then
    s.edit:insmode(not s.edit:insmode())
  elseif k == 'f1' then
    help_mode = not help_mode
  elseif (k == 'u' or k == 'z') and input.keydown 'ctrl' then
    s.edit:undo()
  elseif k == 'keypad .' or k == 'delete' then
    s.edit:delete()
  elseif k == 'x' and input.keydown 'ctrl' then
    s.edit:cut()
  elseif k == 'y' and input.keydown 'ctrl' then
    s.edit:cutline()
  elseif k == 'd' and input.keydown 'ctrl' then
    s.edit:dupline()
  elseif k == 'c' and input.keydown 'ctrl' then
    s.edit:cut(true)
  elseif k == 'v' and input.keydown 'ctrl' then
    s.edit:paste()
  elseif k== 'f4' then
    inp_mode = not inp_mode
    if inp_mode then
      inp_mode = 'open'
      inp.edit:set(FILE)
      inp.edit:move(128)
    end
  elseif (k == 'h' and input.keydown 'ctrl') or
    (k == 'f7' and input.keydown 'shift') then
    if inp.hist and inp.hist.search then
      s:search(inp.hist.search[#inp.hist.search])
    end
  elseif (k == 'f' and input.keydown 'ctrl') or k == 'f7' then
    inp_mode = not inp_mode
    if inp_mode then
      inp_mode = 'search'
    end
  elseif k == 'l' and input.keydown 'ctrl' then
    inp_mode = not inp_mode
    if inp_mode then
      inp_mode = 'goto'
    end
  end
  s.edit:select()
end

function buff:search(t)
  local x1, y1, x2, y2 = self.edit:search(t)
  if x1 then
    self.edit:select(x1, y1, x2, y2)
    self.edit:move(x1, y1+math.floor(self.lines/2))
    self.edit:move(x1, y1)
    return true
  end
end

b = buff.new(FILE)
b:resize(W, H - b.sph)
inp = buff.new(false, 0, H - b.sph, W, b.sph)
inp.status = false

function inp:history(t)
  if t == '' then return end
  self.hist = self.hist or { }
  self.hist[inp_mode] = self.hist[inp_mode] or {}
  local h = self.hist[inp_mode]
  if #h == 0 or h[#h] ~= t then
    table.insert(h, t)
  end
  if #t > 128 then table.remove(t, 1) end
  h.hidx = #h + 1
end

function inp:hprev()
  self.hist = self.hist or { }
  local h = self.hist[inp_mode] or {}
  local idx = h.hidx or #h + 1
  if idx == 1 then return end
  h.hidx = idx - 1
  self.edit:set(h[h.hidx])
  self.edit:move(false, 1)
  self.edit:toend()
end

function inp:hnext()
  self.hist = self.hist or { }
  local h = self.hist[inp_mode] or {}
  local idx = h.hidx or #h + 1
  if idx > #h then return end
  h.hidx = idx + 1
  self.edit:set(h[h.hidx] or '')
  self.edit:move(false, 1)
  self.edit:toend()
end

function inp.edit:newline()
  local s = self
  local t = s:get():stripnl()
  if inp_mode == 'search' then
    b:search(t)
  elseif inp_mode == 'goto' then
    b:jump(math.floor(tonumber(t) or 1))
  elseif inp_mode == 'open' then
    if not t:empty() then
      FILE = t
      b = buff.new(FILE)
    end
  elseif inp_mode == 'write' then
    if not t:empty() then
      b.fname = t
      FILE = t
      b:write()
    end
  end
  inp:history(t)
  s:set ''
  s:move(1, 1)
  inp_mode = false
end

function get_buff()
  return inp_mode and inp or b
end

mixer.done()

local HELP = [[Keys:
F2,ctrl-s    - save
shift-f2     - save as
ctrl-l       - jump to line
home,ctrl-a  - line begin
end,ctrl-e   - line end
pageup       - scroll up
pagedown     - scroll down
F7,ctrl-f    - search
ctrl-h       - search again
cursor keys  - move
shift+cursor - select (+alt vertical block)
ctrl-x       - cut&copy selection
ctrl-c       - copy selection
ctrl-v       - paste selection
ctrl-y       - remove line
ctrl-z       - undo
ctrl-w       - select inside line
ctrl-d       - duplicate line
alt-w        - wrap text
ins          - insert mode
F4           - open another file (no save!)
F5           - run!
F8           - run sprite editor
F9           - run synth editor
shift-esc    - return to editor (from F5/F8/F9 mode)
]]

while sys.running() do
  if idle_mode then -- resume?
    gfx.border(conf.brd)
    mixer.done()
    sys.hidemouse(false)
    screen:nooffset()
    screen:noclip()
    sys.input(true) -- clear input
    sys.event_filter().resized = conf.scalable
    gfx.win(W, H)
    if idle_mode == 'voices' then
      if not b:selected() then
        b:import('__voices__', 'data.syn')
        b:import('__songs__', 'data.sng')
      else
        b:readsel('data.syn')
      end
    elseif idle_mode == 'spr' then
      if not b:selected() then
        b:import('__spr__', 'data.spr')
        b:import('__map__', 'data.map')
      else
        b:readsel('data.spr')
      end
    end
    idle_mode = false
  end
  while help_mode do
    screen:clear(conf.bg)
    gfx.print(HELP, 0, 0, conf.fg, true)
    local rr = sys.input()
    if rr == 'keydown' then
      help_mode = 1
    elseif rr == 'keyup' and help_mode == 1 then
      help_mode = false
      break
    end
    coroutine.yield()
  end
  local r, v, a = sys.input()
  if r == 'resized' or r == 'exposed' then
    W, H = v - conf.scalable_font_sz, a - conf.scalable_font_sz
    gfx.win(W, H)
    b:resize(W, H - b.sph)
    inp:resize(W, b.sph)
    inp.y = H - b.sph
    inp.w = W
    if inp_mode then b:show() end
  elseif r == 'keydown' then
    get_buff():keydown(v)
  elseif r == 'keyup' then
    get_buff():keyup(v)
  elseif r == 'text' then
    if not input.keydown 'alt' then
      local x, y = get_buff().edit:cursor()
      if get_buff().edit:insel(x, y) then
        get_buff().edit:input(v, true)
      else
        get_buff().edit:unselect()
        get_buff().edit:input(v)
      end
    end
  elseif r and r:startswith 'mouse' then
    get_buff():mouse(r, v)
  end
  if not idle_mode then
    if not gfx.framedrop() then
      get_buff():show()
    end
    gfx.flip(conf.cursor_blink and 1/10 or 1, true)
  end
end
