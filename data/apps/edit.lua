local editor = require "editor"
gfx.win(385, 380)
--local sfont = gfx.font('demo/iosevka.ttf',12)
local idle_mode
local inp_mode
local help_mode
local sfont = font
local W, H = screen:size()
local conf = {
  fg = 0,
  bg = 16,
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
gfx.border(conf.brd)

local FILE = ARGS[2] or 'main.lua'

local buff = {
}
buff.__index = buff

local glyph_cache = {}

local function clone(t)
  local l = {}
  for _, v in ipairs(t) do
    table.insert(l, v)
  end
  return l
end

function glyph(t, col)
  col = col or conf.fg
  local key = string.format("%s-%s", t, col)
  if glyph_cache[key] then
    return glyph_cache[key]
  end
  glyph_cache[key] = sfont:text(t, col)
  return glyph_cache[key]
end

function buff.new(fname, x, y, w, h)
  local b = { edit = editor.new(), fname = fname,
    x = x or 0, y = y or 0, w = w or W, h = h or H }
  local f = fname and io.open(fname, "rb")
  b.text = b.edit.lines
  if f then
    for l in f:lines() do
      l = l:gsub("\t", "  ")
      table.insert(b.text, utf.chars(l))
    end
    f:close()
  end
  b.spw, b.sph = sfont:size(" ")
  b.columns = math.floor(b.w / b.spw)
  b.lines = math.floor(b.h / b.sph) - 1 -- status line
  b.edit:size(b.columns, b.lines)
  setmetatable(b, buff)
  return b
end

function buff:lookuptag(tag)
  local s = self
  local insect
  local y1, y2
  for k, l in ipairs(s.text) do
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
    local str = table.concat(s.text[y], ""):gsub("%]%]$", ""):gsub("^.[^%[]*%[%[", "")
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
    table.remove(s.text, y1)
  end
  table.insert(s.text, y1, utf.chars(string.format("local %s = [[", tag)))
  for l in f:lines() do
    lines = lines + 1
    table.insert(s.text, y1 + lines, utf.chars(l))
  end
  table.insert(s.text, y1 + lines + 1, utf.chars "]]")
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
  if not f then
    return
  end
  local eof = #s.text
  for k=#s.text,1,-1 do
    if #s.text[k] ~= 0 then
      eof = k
      break
    end
  end
  for k, l in ipairs(s.text) do
    l = table.concat(l, ''):gsub("[ \t]+$", "") -- strip
    f:write(l.."\n")
    if k == eof then
      break
    end
  end
  f:close()
  s.edit.dirty = false
  print(string.format("%s written", s.fname))
end

function buff:cursor()
  local s = self
  if math.floor(sys.time()*4) % 2 == 1 then
    return
  end
  local px, py = s.edit:coord(s.edit:cursor())
  px, py = (px - 1)*s.spw, (py - 1) * s.sph
  for y=py, py + s.sph-1 do
    for x=px, px + s.spw-1 do
      local r, g, b = screen:val(s.x + x, s.y + y)
      r = bit.bxor(r, 255)
      g = bit.bxor(g, 255)
      b = bit.bxor(b, 255)
      screen:val(s.x + x, s.y + y, {r, g, b, 255})
    end
  end
end

function buff:status()
  local s = self
  local cx, cy = self.edit:cursor()
  local info = string.format("%s%s %2d:%-2d",
    s.edit.dirty and '*' or '', s.fname, cx, cy)
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

function buff:colorize(l)
  if not conf.syntax then
    return {}
  end
  local pre = ' '
  local start
  local key
  local cols = {}
  local beg
  local k, c = 1, 0
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
    cols = self:colorize(l)
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
  if k:find 'shift' then
    s.edit:select(true)
  elseif k == 'up' then
    s.edit:move(false, cy - 1)
  elseif k == 'down' then
    s.edit:move(false, cy + 1)
  elseif k == 'right' then
    s.edit:move(cx + 1)
  elseif k == 'left' then
    s.edit:move(cx - 1)
  elseif k == 'home' or k == 'keypad 7' or
    (k == 'a' and input.keydown 'ctrl') then
    s.edit:move(1)
  elseif k == 'end' or k == 'keypad 1' or
    (k == 'e' and input.keydown 'ctrl') then
    s.edit:move(#s.text[cy] + 1)
  elseif k == 'pagedown' or k == 'keypad 3' then
    s.edit:move(false, cy + s.lines)
  elseif k == 'pageup' or k == 'keypad 9' then
    s.edit:move(false, cy - s.lines)
  elseif k == 'return' or k == 'keypad enter' then
    s.edit:newline(true)
  elseif k == 'backspace' then
    s.edit:backspace()
  elseif k == 'tab' then
    s.edit:input("  ")
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
    os.remove('voices.syn')
    os.remove('songs.syn')
    if not s:selected() then
      s:export ('__voices__', 'voices.syn')
      s:export ('__songs__', 'songs.syn')
    else
      s:writesel('voices.syn')
    end
    idle_mode = 'voices'
    s:exec("voiced", 'voices.syn')
  elseif k == 'f5' then
    s:write()
    idle_mode = 'run'
    s:exec(FILE)
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
  elseif k == 'c' and input.keydown 'ctrl' then
    s.edit:cut(true)
  elseif k == 'v' and input.keydown 'ctrl' then
    s.edit:paste()
  elseif k== 'f4' then
    inp_mode = not inp_mode
    if inp_mode then
      inp_mode = 'open'
    end
  elseif (k == 'f' and input.keydown 'ctrl') or k == 'f7' then
    inp_mode = not inp_mode
    if inp_mode then
      local t =  s:selected()
      if t then
        inp_mode = false
        s:search(t)
      else
        inp_mode = 'search'
      end
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
    self.edit:move(x1, y1)
    return true
  end
end

local b = buff.new(FILE)
local inp = buff.new(false, 0, H - b.sph, W, b.sph)
inp.status = false
inp.lines = 1
inp.edit:size(W, b.sph)

function inp.edit:newline()
  local s = self
  if inp_mode == 'search' then
    b:search(table.concat(s.lines[1] or {}, ''))
  elseif inp_mode == 'goto' then
    b:jump(math.floor(tonumber(table.concat(s.lines[1] or {}, '')) or 1))
  elseif inp_mode == 'open' then
    local f = table.concat(s.lines[1] or {}, '')
    if f ~= '' then
      FILE = f
      b = buff.new(FILE)
    end
  end
  s:set ''
  s:move(1, 1)
  inp.text = s.lines
  inp_mode = false
end

function get_buff()
  return inp_mode and inp or b
end

mixer.done()

local HELP = [[Keys:
F2,ctrl-s    - save
ctrl-l       - jump to line
home,ctrl-a  - line begin
end,ctrl-e   - line end
pageup       - scroll up
pagedown     - scroll down
F7,ctrl-f    - search
cursor keys  - move
shift+cursor - select
ctrl-x       - cut&copy selection
ctrl-c       - copy selection
ctrl-v       - paste selection
ctrl-z       - undo
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
    gfx.win(W, H)
    if idle_mode == 'voices' then
      if not b:selected() then
        b:import('__voices__', 'voices.syn')
        b:import('__songs__', 'songs.syn')
      else
        b:readsel('voices.syn')
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
    if sys.input() == 'keydown' then
      help_mode = false
      break
    end
    coroutine.yield()
  end
  local r, v = sys.input()
  if r == 'keydown' then
    get_buff():keydown(v)
  elseif r == 'keyup' then
    get_buff():keyup(v)
  elseif r == 'text' then
    get_buff().edit:unselect()
    get_buff().edit:input(v)
  elseif r and r:startswith 'mouse' then
    get_buff():mouse(r, v)
  end
  if not idle_mode then
    if not gfx.framedrop() then
      get_buff():show()
    end
    gfx.flip(1/10, true)
  end
end
