local win = require "red/win"
local frame = require "red/frame"
local proc = require "red/proc"
local uri = require "red/uri"
local presets = require "red/presets"
local dumper = require "dump"

sys.title "red"

local conf = {
  fg = 0,
  bg = 16,
  cursor = 0,
  button = { 0x88, 0x88, 0xcc},
  active = { 0xff, 0x88, 0xcc},
  font = DATADIR..'/fonts/iosevka-light.ttf',
  font_sz = 14,
  ts = 4,
  spaces_tab = false, -- don't be evil!
  brd = { 0xde, 0xde, 0xde },
  menu = 17,
  hl = { 0xee, 0xee, 0x9e },
  process_hz = 1/50,
  unknown_sym = "?",
  cr_sym = '^',
}

local ops, optarg = sys.getopt(ARGS, {
  fs = conf.font_sz,
})
conf.font_sz = ops.fs

win:init(conf)

local scr = win.scr

local function filename_line(fn)
  local a = fn:split ':'
  if #a > 1 and tonumber(a[#a]) then
    local nr = tonumber(table.remove(a, #a))
    return table.concat(a, ':'), nr
  end
  return fn, 0
end

local function dirpath(base, file)
  file = file or ''
  return (base .. '/' .. file):gsub("/+", "/")
end

local function readdir(fn)
  local dir = sys.readdir(fn) or {}
  for k, v in ipairs(dir) do
    dir[k] = dir[k]:esc()
    if sys.isdir(fn .. v) then
      dir[k] = dir[k] .. '/'
    end
  end
  table.sort(dir, function(a, b)
    if a:endswith '/' and b:endswith '/' then
      return a < b
    elseif a:endswith '/' and not b:endswith '/' then
      return true
    elseif not a:endswith '/' and b:endswith '/' then
      return false
    end
    return a < b
  end)
  return dir
end

function string.esc(str)
  str = str:gsub("\\?[ ]",
    { [" "] = "\\ ", ["\\ "] = "\\\\ " })
  return str
end

function string.unesc(str)
  str = str:gsub("\\?[\\ ]", { ['\\ '] = ' ',
    ['\\\\'] = '\\' })
  return str
end

function string.escsplit(str, ...)
  str = str:gsub("\\?[\\ ]", { ['\\ '] = '\1',
    ['\\\\'] = '\2' })
  local a = str:split(...)
  for k, v in ipairs(a) do
    a[k] = v:gsub("[\1\2]", { ['\1'] = " ",
    ['\2'] = "\\" })
  end
  return a
end

local function make_move_cursor()
  local cur_size = math.round(scr.sph)
  local cur_border = math.ceil(scr.sph/8)
  local cur = gfx.new(cur_size, cur_size)
  cur:clear(conf.button)
  cur:clear(cur_border, cur_border, cur_size - 2*cur_border,
    cur_size - 2*cur_border, {0, 0, 0, 0})
  return cur
end

local function make_text_cursor()
  local d = 1*SCALE
  local w = math.floor(3*d)
  if w % 2 == 0 then
    w = w + 1
  end
  local c = math.floor(w/2)
  local cur = gfx.new(w, scr.sph)
  d = math.floor(d/2)
  cur:fill_rect(c - d, 0, c+d, scr.sph - 1, conf.cursor)
  cur:fill_rect(0, 0, w, w-1, conf.cursor)
  cur:fill_rect(0, scr.sph - w, w, scr.sph - 1, conf.cursor)
  return cur
end

conf.move_cursor = make_move_cursor()
conf.text_cursor = make_text_cursor()

function win:show_cursor(x, y, img)
  local w, h
  if x and x < 0 then x = 0 end
  if y and y < 0 then y = 0 end
  if self.cur_img then
    self.cur_img.bg:copy(screen, self.cur_img.x, self.cur_img.y)
    if not img then
      self.cur_img = nil
      return
    end
  elseif img then
    w, h = img:size()
    self.cur_img = { img = img, bg = gfx.new(w, h) }
  else
    return
  end
  screen:copy(x, y, w, h, self.cur_img.bg)
  self.cur_img.img:blend(screen, x, y)
  self.cur_img.x = x
  self.cur_img.y = y
end

function win:proc(t)
  local a = t:split(1)

  if t:startswith'!' then
    a[1] = '!'
    a[2] = t:sub(2)
  end
  if type(proc[a[1]]) == 'function' then
    self:run(proc[a[1]], a[2])
    return true
  end
end

function win:exec(t)
--  if t == ':?' then
--    self.buf:input(tostring(self.frame:win().buf:line_nr()))
--    return true
--  end
  t = t:unesc()

  if self:proc(t) then
    return true
  end

  if self.buf.fname and self.buf.fname:endswith '/' then
    t = (self.buf.fname .. t):gsub('/+', '/')
  end

  local fr = self.frame.frame and self.frame.frame or self.frame
  if fr:win_by_name(t) then
    return fr:file(t)
  end

  for _, u in ipairs(uri) do
    if t:find(u[1]) then
      print(string.format(u[2], t))
      os.execute(string.format(u[2], t))
      return
    end
  end

  local ff = filename_line(t)

  if not sys.isdir(ff) then
    local f = io.open(ff, "r")
    if not f then
      return
    end
    f:close()
  end
  self.frame:file(t)
end

local menu = require "red/menu"

menu.bg = conf.menu

function menu:show()
  win.show(self)
  screen:offset(self.x, self.y)
  screen:line(scr.spw, self.h - 1, self.w, self.h - 1, conf.button)
  screen:nooffset()
end

function menu:scroller()
  screen:clear(self.x, self.y, scr.spw, self.h,
    self.frame:dirty() and
    self.frame:win():dirty() and
    conf.active or conf.button)
  screen:rect(self.x, self.y,
    self.x + scr.spw - 1,
    self.y + self.h - 1, conf.fg)
end

function frame:win_by_name(f)
  f = filename_line(f)
  for v, k in self:for_win() do
    if v.buf.fname == f then
      return v, k
    end
  end
end

function frame:push_win(b)
  local k = self:find_win(b)
  if not k then return end
  self:swap_win(b, k)
end

function frame:swap_win(b, k)
  if k then
    self:del_win(k)
    if k > 2 then
      self:add(self:del_win(1), k)
    end
  end
  self:add_win(b, 1)
  self:update(true)
  self:refresh()
end

function frame:file(f)
  local fn, nr = filename_line(f)
  local dir = sys.isdir(fn)
  if dir then
    fn = dirpath(fn)
  end
  local b, k = self:win_by_name(f)

  if b then -- already opened
    if self:win() == b then -- already visible
      self:win():toline(nr)
      return
    end
    self:swap_win(b, k)
    self:win():toline(nr)
    return
  end

  b = win:new(fn)

  if dir then
    dir = readdir(fn)
    for _, v in ipairs(dir) do
      b.buf:append(v..'\n')
    end
  elseif not fn:startswith '+' then
    b.conf = presets.get(fn) or {}
    b:file(fn)
  end
  self:swap_win(b)
  self:win():toline(nr)
end

function frame:getfilename()
  if not self.frame then
    return "./"
  end
  local t = self:menu().buf:gettext():split('|', 1)[1]
  t = (t:escsplit()[1] or ''):strip()
  return not t:empty() and t
end

function frame:show()
  if scr.grab then return end
  for _, v in ipairs(self.childs) do
    if v:show() then
      break
    end
  end
end

function frame:update(force)
  local o = self:menu().buf:gettext()
  local d = o:find('|', 1, true)
  if d then
    o = o:sub(d)
  end
  local t = ''
  local fn = not force and self:getfilename()
  for c, i in self:for_win() do
    if i == 1 and fn and fn ~= c.buf.fname then
      while self.frame:win_by_name(fn) do
        fn = '~' .. fn
      end
      c.buf.fname = fn
      c.conf = presets.get(fn) or {}
    end
    t = t .. c.buf.fname:esc() .. ' '
  end
  if self:win() then
    -- self:win():dirty(self:win().buf:dirty())
    local cur = self:win()
    if self:win():dirty() and cur.buf:isfile() then
      t = t .. 'Put '
    end
    t = t .. 'Close '
    t = t .. 'Get '
--    t = t .. ':'..tostring(cur.buf:line_nr()) .. ' '
  end
  if self.frame:win_nr() > 1 then
    t = t .. 'Delcol '
  end
  if not d then
    t = t .. '| '
    o = o:strip()
  end
  local old = utf.chars(self:menu().buf:gettext())
  local new = utf.chars(t..o)
  for i = 1, math.min(#old, #new) do
    if i == self:menu().buf.cur then
      break
    end
    if old[i] ~= new[i] then
      self:menu().buf.cur = self:menu().buf.cur + #new - #old
      break
    end
  end
  self:menu():set(new)
end

local framemenu = menu:new()
framemenu.cmd = {}

function framemenu:event(r, v, a, b)
  local mx, my, mb = input.mouse()
  if r == 'mousedown' and (v == 'left' or v == 'right') then
    local x, y = a - self.x, b - self.y
    if x >= 0 and x < scr.spw and y >= 0 and y < self.h then
      self.grab = true
      scr.grab = true
      return true
    end
  elseif r == 'mousemotion' then
    if self.grab then
      if mb.left and not mb.right then -- resize
        self.frame.posx = math.max(scr.spw, v)
        self.frame.frame:refresh()
        return true
      elseif mb.right then
        self:show_cursor(mx, my, conf.move_cursor)
        return true
      end
    end
  elseif r == 'mouseup' and (v == 'left' or v == 'right') then
    if self.grab then
      self.grab = false
      scr.grab = false
      self:show_cursor()
      if v == 'left' then -- resize
        self.frame.posx = math.max(scr.spw, a)
        self.frame.frame:refresh()
        return true
      elseif v == 'right' then -- move
        self.frame.frame:move(math.max(scr.spw, a), self.frame)
        return true
      end
    end
  end
  return menu.event(self, r, v, a, b)
end

function framemenu:new(...)
  local r = menu.new(self, ...)
  r:set '| New '
  return r
end

function framemenu.cmd:Delcol()
  local main = self.frame.frame
  if main:win_nr() <= 1 then return end

  local idx = main:find_win(self.frame)
  main:del_win(idx)
  if idx > main:win_nr() then idx = main:win_nr() end

  local v = self.frame:dirty()
  if v then
    main:add_win(self.frame, idx)
    self.frame:err("File %q is not saved!", v.buf.fname)
    v:nodirty()
  end
  main:win(idx):update(true)
  self.frame.frame:refresh()
end


function framemenu.cmd:Put()
  local b = self.frame:win()
  if not b then
    return
  end
  local f = self.frame:getfilename()
  if f then
    b.buf:save(f)
    b:nodirty()
  end
  self.frame:update()
end

function framemenu.cmd:Get()
  local b = self.frame:win()
  if not b then
    return
  end
  local f = self.frame:getfilename()
  if f then
    b.buf:load(f)
    b:nodirty()
  end
  self.frame:update()
end

function framemenu.cmd:Close()
  local c = self.frame:win()
  if not c then return end
  if c.buf:isfile() and c:dirty() then
    self.frame:err("File %q is not saved!", c.buf.fname)
    c:nodirty()
  else
    c:killproc()
    self.frame:del(c)
  end
  self.frame:update(true)
  self.frame:refresh()
end

function framemenu.cmd:New()
  self.frame:file(self.frame.frame:getnewfile())
  self.frame:refresh()
end

local mainmenu = menu:new()
mainmenu.cmd = {}

mainmenu.buf:set 'Newcol Help PutAll Dump Exit'


function mainmenu:scroller()
  screen:clear(self.x, self.y, scr.spw, self.h,
    self.frame:dirty() and conf.active or conf.button)
  screen:rect(self.x, self.y,
    self.x + scr.spw - 1,
    self.y + self.h - 1, conf.fg)
end

function mainmenu.cmd:Dump()
  local d = {}
  d.menu = self.buf:gettext()
  for f in self.frame:for_win() do
    local c = {}
    for w in f:for_win() do
      local b = { fname = string.format("%s", w.buf.fname) }
      table.insert(c, 1, b)
      b.line = w.buf:line_nr()
      if not w.buf:isfile() or true then -- dump all!
        b.text = w.buf:gettext()
      end
    end
    c.menu = f:menu().buf:gettext()
    table.insert(d, c)
  end
  dumper.save("red.dump", d)
end

function mainmenu.cmd:PutAll()
  for f in self.frame:for_win() do
    for w in f:for_win() do
      if w.buf:isfile() and w.buf:dirty() then
        local r, e = w.buf:save()
        if not r then
          f:err(e)
        else
          w:nodirty()
        end
      end
    end
  end
end

function mainmenu.cmd:Help()
  local w = self.frame:win():open_err("+Help")
  w:clear()
  w:printf([[RED - Rein EDitor

esc          - cut, select last typed block
ctrl-s       - Save (Put) current buffer
ctrl-x,c,v   - cut, copy, paste
ctrl-w       - smart selection
ctrl-a,e     - line start, end
ctrl-k       - kill to eol
ctrl-z       - undo
shift-arrows - select

Plan9 acme like mouse chording and actions

To move file buffer between columns use mouse 2nd button drag&drop of menu button.

right mb     - search
alt+rmb      - search back
middle mb    - exec cmd

Some built-in commands:

select lua-regexp   - find in all text globally
find lua-regexp     - find in line
sub /lua-regexp/b/  - change a to b by lines
gsub /lua-regexp/b/ - chnage a to b global
!cmd                - run and show output
]])
  w.buf.cur = 1
  w:toline(1, false)
end

function mainmenu.cmd:Exit()
  local w = self.frame:dirty()
  if w then
--    w.frame:err("File %q is not saved!", w.buf.fname)
    w.frame:push_win(w)
    return
  end
  os.exit(0)
end

function mainmenu.cmd:Newcol()
  self.frame:add(frame:new(framemenu:new()))
  for v in self.frame:for_win() do
    v:update()
  end
  self.frame:refresh()
end

local mainwin = frame:new()

function mainwin:update()
end

function mainwin:getnewfile()
  local max = 0
  for f in self:for_win() do
    for w in f:for_win() do
      if w.buf and w.buf.fname and
        w.buf.fname:startswith 'new' then
        local nr = tonumber(w.buf.fname:sub(4))
        if nr and nr > max then
          max = nr
        end
      end
    end
  end
  return string.format("new%d", max + 1)
end

function mainwin:geom(x, y, w, h)
  local menu = self:menu()
  local scale = 1
  if self.w then
    scale = w / self.w
  end
  self.x, self.y, self.w, self.h = x, y, w, h
  menu:geom(x, y, w, 0)
  menu:geom(x, y, w, menu:realheight())
  menu.pos = math.max(0, menu.pos)
  menu.pos = math.min(menu.pos, #menu.buf.text)

  local pos = menu:bottom()

  if self:win_nr() == 0 then
    screen:clear(x, pos, w, h - pos, 7)
    return
  end
  local dw = math.floor(w / self:win_nr())
  h = h - pos
  for c, i in self:for_win() do
    c.posx = c.posx or c.x
    if c.posx then c.posx = math.floor(c.posx * scale) else
      c.posx = x + (i-1)*dw
    end
  end
  table.sort(self.childs, function(a, b) return (a.posx or -1) < (b.posx or -1) end)
  for c, i in self:for_win() do
    local r = self:win(i+1) or { posx = self.w }
    if i == 1 then
      c.posx = 0
    end
    c:geom(c.posx, y + pos, r.posx - c.posx, h)
  end
end

function mainwin:move(x, w)
  for c in self:for_win() do
    if x >= c.x and x < c.x + c.w then -- move it!
      if c:win_by_name(w:win().buf.fname) then
        return
      end
      local b = w:del_win()
      if not b then return end
      c:add_win(b, 1)
      c:update(true)
      w:update(true)
      self:refresh()
      return true
    end
  end
end

function mainwin:dirty()
  for f in self:for_win() do
    local fn = f:dirty()
    if fn then return fn end
  end
end

function frame:dirty()
  for w in self:for_win() do
    if w:dirty() then
      return w
    end
  end
end

function menu:winmenu()
  return self.frame:win()
end
function win:winmenu()
end
function mainmenu:winmenu()
end

function menu:output(n)
  return self.frame:open_err(n)
end
function win:output(n)
  return self
end
function mainmenu:output(n)
  return self.frame:active_frame():open_err(n)
end

local main = mainwin:new(mainmenu)

function main:win_by_name(n)
  for fr in self:for_win() do
    local r, v = fr:win_by_name(n)
    if r then return r, v end
  end
end

function main:file(n)
  local found
  for fr in self:for_win() do
    local w = fr:win_by_name(n)
    if w then
      w.frame:file(n)
      found = true
    end
  end
  if found then return end
  local fr = self:active_frame()
  return fr:file(n)
end

function main:active_frame()
  local i, max = 1, 10000
  for f, k in self:for_win() do
    local nr = f:win_nr()
    if nr < max then
      i = k
      max = nr
    end
  end
  return self:win(i)
end

main:geom(0, 0, scr.w, scr.h)

local function load_dump(f)
  local d = dumper.load(f)
  if not d then return end
  for i, v in ipairs(d) do
    mainmenu.cmd.Newcol(mainmenu)
    for _, b in ipairs(v) do
      main:win(i):file(b.fname)
      if b.text then
        local ww = main:win(i):win()
        ww:set(b.text)
        ww:dirty(ww.buf:dirty())
      end
      if b.line then
        main:win(i):win():toline(b.line, false)
      end
    end
    if v.menu then
      main:win(i):menu().buf:set(v.menu)
    end
  end
  if d.menu then
    main:menu():set(d.menu)
  end
  return true
end

if #ARGS > 1 then
  mainmenu.cmd.Newcol(mainmenu)
  for i = 2, #ARGS do
    main:win():file(ARGS[i])
  end
else
  if not load_dump "red.dump" then
    mainmenu.cmd.Newcol(mainmenu)
    main:win():file(main:getnewfile())
  end
end

while sys.running() do
  local r, v, a, b = sys.input()
  if r == 'resized' or r == 'exposed' then
    win:init(conf)
    main:geom(0, 0, scr.w, scr.h)
  else
    main:event(r, v, a, b)
  end
  main:show()
  if main:process() then
    gfx.flip(conf.process_hz, true)
  else
    gfx.flip(1, true)
  end
end
