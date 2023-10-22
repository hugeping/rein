local win = require "red/win"
local frame = require "red/frame"
local proc = require "red/proc"
local uri = require "red/uri"
local presets = require "red/presets"
local dumper = require "dump"
local HISTFILE = DATADIR .. '/red.hist'

sys.title "red"

local conf = {
  fg = 0,
  bg = 16,
  cursor = 0,
  cursor_over = 8,
  button = { 0x88, 0x88, 0xcc},
  active = { 0xff, 0x88, 0xcc},
  font = DATADIR..'/fonts/iosevka-light.ttf',
  font_sz = 14,
  ts = 4,
  spaces_tab = false, -- don't be evil!
  trim_spaces = false,
  brd = { 0xde, 0xde, 0xde },
  menu = 17,
  hl = { 0xee, 0xee, 0x9e },
  idle_hz = 1/10,
  proc_hz = 1/50,
  unknown_sym = "?",
  cr_sym = '^',
  nodump = false,
--  syntax = true,
  colorize_win = 4096,
--  histfile = true,
  emptymenu = '| New ',
}

local win_keys = {
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

local function try_lua(file)
  if not io.access(file) then return end
  local r, e = pcall(function() return dofile(file) end)
  if not r then
    print(string.format("Error parsing: %q: %s", file, e))
  end
  return r and e
end

local function load_conf(dir)
  local merge = {
    { "conf.lua", conf, table.merge },
    { "presets.lua", presets, function(_, t) presets = t end },
    { "uri.lua", uri, function(_, t) uri = t end },
    { "proc.lua", proc, table.merge },
    { "keys.lua", win_keys, function(d, t) table.append(d, table.unpack(t)) end },
  }
  for _, v in ipairs(merge) do
    local t = try_lua(dir .. '/'.. v[1])
    if type(t) == 'table' then
      v[3](v[2], t)
    end
  end
end

local function parse_options(args)
  local ops, optarg = sys.getopt(args, {
    fs = conf.font_sz,
    nodump = true,
    confdir = false,
  })
  local ret = {}
  for i = optarg, #args do
    table.insert(ret, args[i])
  end
  if ops.confdir and sys.isdir(ops.confdir) then
    load_conf(ops.confdir)
    HISTFILE = ops.confdir .. '/red.hist'
  end
  conf.font_sz = ops.fs
  conf.nodump = ops.nodump
  return ret
end

ARGS = parse_options(ARGS)

function presets.get(fname)
  for _, v in ipairs(presets) do
    if fname:find(v[1]) then
      return v[2]
    end
  end
end

win:init(conf)
win:make_keybinds(win_keys)

local scr = win.scr

local histfile = (conf.histfile and dumper.load(HISTFILE)) or {}

function win:histfile_add()
  if not conf.histfile then
    return
  end
  histfile = dumper.load(HISTFILE) or {}
  table.insert(histfile, 1, { sys.realpath(self.buf.fname), self.buf.cur or 1 })
  if #histfile > 128 then
    table.remove(histfile, #histfile)
  end
  dumper.save(HISTFILE, histfile)
end

function win:histfile_get()
  for _, v in ipairs(histfile) do
    if v[1] == sys.realpath(self.buf.fname) then
      self:cur(v[2])
      return true
    end
  end
end

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
    if sys.isdir(fn .. '/' .. v) then
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

function win:readdir(f)
  local dir = readdir(f)
  for _, v in ipairs(dir) do
    self.buf:append(v..'\n', true)
  end
  return
end

local function make_icon()
  local logo = gfx.new(64,64)
  logo:clear(16)
  local d = 6
  logo:clear(d, d, 64-2*d, 64-2*d, { 255, 0, 0 })
  return logo
end
gfx.icon(make_icon())

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
function string.escencode(str)
  str = str:gsub("\\?[\\ ]", { ['\\ '] = '\1',
    ['\\\\'] = '\2' })
  return str
end

function string.escdecode(str)
  str = str:gsub("[\1\2]", { ['\1'] = " ", ['\2'] = "\\" })
  return str
end

function string.escsplit(str, ...)
  str = str:escencode()
  local a = str:split(...)
  for k, v in ipairs(a) do
    a[k] = v:escdecode()
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

local function make_text_cursor(color)
  local d = 1*SCALE
  local w = math.floor(3*d)
  if w % 2 == 0 then
    w = w + 1
  end
  local c = math.floor(w/2)
  local cur = gfx.new(w, scr.sph)
  d = math.floor(d/2)
  cur:fill_rect(c - d, 0, c+d, scr.sph - 1, color)
  cur:fill_rect(0, 0, w, w-1, color)
  cur:fill_rect(0, scr.sph - w, w, scr.sph - 1, color)
  return cur
end

conf.move_cursor = make_move_cursor()
conf.text_cursor = make_text_cursor(conf.cursor)
conf.text_cursor_over = make_text_cursor(conf.cursor_over)

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

local io_delim = {
  ['<'] = true;
  ['>'] = true;
  ['!'] = true;
  ['|'] = true,
  ['@'] = true,
}

function win:save()
  if not self.buf:isfile() then
    return
  end
  local trim = self:getconf 'trim_spaces'
  if trim then
    local nr = self.buf:line_nr()
    self.buf:set(self.buf:gettext():gsub('[ \t]+\n', '\n'):gsub("[ \t\n]+$", "\n"))
    if self.buf:line_nr() ~= nr then
      self:toline(nr, false)
    end
  end
  local r, e = self.buf:save()
  if r then
    self:nodirty()
  end
  return r, e
end

function win:proc(t)
  local a = t:split(1)

  if io_delim[t:sub(1,1)] then
    a[1] = t:sub(1, 1)
    a[2] = t:sub(2)
  end
  if type(proc[a[1]]) == 'function' then
    self:run(proc[a[1]], a[2])
    return true
  end
end

function win:path(t)
  local a = self.cwd
  if not a then return t end
  a = a:gsub("/+$", "")
  a = a:split('/')
  local b = (sys.realpath "./")
  b = b:split('/')
  local p = ''
  local k = #b + 1
  for i = 1, #b do
    if b[i] ~= a[i] then
      k = i
      p = p .. string.rep('../', #b - i + 1)
      break
    end
  end
  for i = k, #a do
    p = p .. a[i] .. '/'
  end
  return p .. (t or '')
end

function win:exec(t)
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
      proc['!'](self, string.format(u[2], t))
      return
    end
  end

  t = self:path(t)
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
  if not b or self:win() == b then
    return
  end
  local k = self:find_win(b)
  self.prev_win = 2
  if k then
    self.prev_win = k
    self:del_win(k)
    if k > 2 then
      self:add(self:del_win(1), k)
    end
  end
  self:add_win(b, 1)
  self:update(true, true)
  self:refresh()
end

function frame:file(f)
  local fn, nr = filename_line(f)
  local dir = sys.isdir(fn)
  if dir then
    fn = dirpath(fn)
  end
  local b = self:win_by_name(f)
  if b then -- already opened
    self:push_win(b)
    self:win():toline(nr)
    return
  end

  b = win:new(fn)
  b.menu = self:menu().buf:gettext() -- clone menu
  if dir then
    b:set ""
    b:readdir(fn)
    b:cur(1)
  elseif not fn:startswith '+' then
    b.conf = presets.get(fn) or {}
    b:file(fn)
    if nr == 0 and b:histfile_get() then
      self:push_win(b)
      self:win():visible()
      return
    end
  end
  self:push_win(b)
  self:win():toline(nr)
end

function frame:getfilename()
  if not self.frame then
    return "./"
  end
  local t = self:menu().buf:gettext():split('|', 1)[1]
  if not t then return end
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

function frame:update(force, pop)
  local sel
  if pop then
    self:menu():set(self:win() and self:win().menu or
      conf.emptymenu)
  elseif self:menu().buf:issel() then
    local s = self:menu().buf:getsel()
    sel = { s = s.s, e = s.e }
  end
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
    local cur = self:win()
    if self:win():dirty() and cur.buf:isfile() then
      t = t .. 'Put '
    end
    t = t .. 'Close '
    t = t .. 'Get '
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
  local menu_delta = #new - #old
  local diff_idx = #new + 1
  for i = 1, math.min(#old, #new) do
    if old[i] ~= new[i] then
      diff_idx = i
      break
    end
  end
  if self:menu().buf.cur >= diff_idx then
    self:menu():cur(self:menu():cur() + menu_delta)
  end
--  if self:menu().buf:insel(diff_idx) then
--    sel = nil
--  end
  self:menu():set(new)
  if self:win() then
    self:win().menu = self:menu():gettext()
  end
  if sel then
    if diff_idx <= sel.s then
      sel.s = sel.s + menu_delta
    end
    if diff_idx <= sel.e then
      sel.e = sel.e + menu_delta
    end
    self:menu().buf:setsel(sel.s, sel.e)
  end
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
  r:set(conf.emptymenu)
  return r
end

function framemenu.cmd:Delcol()
  local main = self.frame.frame
  if main:win_nr() <= 1 then return end

  local idx = main:find_win(self.frame)
  main:del_win(idx)
  if idx > main:win_nr() then idx = main:win_nr() end

  local v = self.frame:dirty()
  if v and not v:clean() then
    main:add_win(self.frame, idx)
    self.frame:err("File %q is not saved!", v.buf.fname)
    v:clean(true)
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
    local r, e = b:save(f)
    if not r then
      self.frame:err(e)
    end
  end
  self.frame:update()
end

function win:Get()
  local f = self.buf.fname
  if not f then return end
  if sys.isdir(f) then
    self:set ""
    self:readdir(f)
    self:cur(1)
  elseif self.buf:isfile() then
    self.buf:load()
    self:dirty(self.buf:dirty())
    self:cur(self:cur())
  end
end

function framemenu.cmd:Get()
  local b = self.frame:win()
  if not b then return end
  b:Get()
  self.frame:update()
end

function framemenu.cmd:Close()
  local c = self.frame:win()
  if not c then return end
  if c.buf:isfile() and c:dirty() and not c:clean() then
    self.frame:err("File %q is not saved!", c.buf.fname)
    c:clean(true)
  else
    c:killproc()
    self.frame:del(c)
  end
  self.frame:update(true, true)
  self.frame:refresh()
end

function framemenu.cmd:New()
  self.frame:file(self.frame.frame:getnewfile())
  self.frame:refresh()
end

local mainmenu = menu:new()
mainmenu.cmd = {}

mainmenu.buf:set 'Newcol Help GetAll PutAll Dump Exit'

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
      b.text = w.buf:gettext()
      b.menu = w.menu
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
        local r, e = w:save()
        if not r then
          f:err(e)
        end
      end
    end
  end
end

function mainmenu.cmd:GetAll()
  for f in self.frame:for_win() do
    for w in f:for_win() do
      w:Get()
    end
    f:update(true)
  end
end

function mainmenu.cmd:Help()
  local w = self.frame:open_err("+Help")
  w:clear()
  w:printf([[
           ___  _______
          / _ \/ __/ _ \
         / , _/ _// // /
        /_/|_/___/____/

       RED - Rein EDitor

Arguments:
  rein [-platform-nojoystick] [-platform-nosound] [-platform-xclip] red [-fs <font size>] [-nodump] [-confdir <dir>]

Keys:
  esc           - cut, select last typed block
  ctrl-s        - Save (Put) current buffer
  ctrl-w        - Close current buffer
  ctrl-o        - Previous buffer
  ctrl-x,c,v    - cut, copy, paste
  alt-w         - smart selection
  ctrl-a,e      - line start, end
  home,end      - line start, end
  ctrl-home,end - first line, last line
  ctrl-k        - kill to eol
  ctrl-z        - undo
  shift-arrows  - select
  insert        - toggle overwrite mode
  ctrl-b        - insert current line in menu (bookmark)

Mouse:
  Plan9 acme like mouse chording and actions

  To move file buffer between columns use mouse 2nd button drag&drop of menu button.

  right mb     - search
  alt+rmb      - search back
  middle mb    - exec command or open

Some built-in commands:

  select lua-regexp   - find in all text globally
  find lua-regexp     - find in line form cur pos
  sub /lua-regexp/b/  - change a to b by lines
  gsub /lua-regexp/b/ - chnage a to b global
  !cmd                - run cmd
  <cmd                - run cmd and get output
  @cmd                - run cmd <text> and get output
]])
  if PLATFORM ~= 'Windows' then
    w:printf([[
  >cmd                - cat <text> | cmd > output
  |cmd                - cat <text> | cmd > edit
]])
  end
  w:printf([[
  fmt [width]         - fmt text by width
  cat <file>          - insert file into the cursor
  dos2unix            - remove \r
  i+/i-               - indent inc/dec
  Run <prog>          - run prog in rein
  Line                - get current line in buffer
  Codepoint           - get codepoint of the sym
  Clear               - clear window
  dump                - hex-dump
  win                 - pseudo acme win

    ** win notes **
    In Unix systems stdin is available.
    esc          - close input
    delete       - try to kill programm
    ctrl-up/down - history
    ls/cd/pwd    - built-in commands

Confdir:
  You can put files: conf.lua, presets.lua, uri.lua, keys.lua and proc here.
]])
  w.buf.cur = 1
  w:toline(1, false)
end

function mainmenu.cmd:Exit()
  self.frame:killproc()
  local w = self.frame:dirty()
  if w and not w:clean() then
    w.frame:err("File %q is not saved!", w.buf.fname)
    w:clean(true)
    sys.running(true)
    return
  end
  for fr in self.frame:for_win() do
    for ww in fr:for_win() do
      if ww.buf:isfile() then
        ww:histfile_add()
      end
    end
  end
  if conf.save_dump then
    mainmenu.cmd.Dump(mainmenu)
  end
  conf.stop = true
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
      if w:win() and c:win_by_name(w:win().buf.fname) then
        return
      end
      local b = w:del_win()
      if not b then return end
      c:push_win(b)
      w:update(true, true)
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
function win:output(n)
  if n then
    return menu.output(self, n)
  end
  return self
end

function menu:output(n)
--  if not n and self.frame:win() then
--    return self.frame:win()
--  end
  n = n or "+Output"
  local w = self.frame.frame:win_by_name(n)
  if w then
    return w.frame:open_err(n)
  end
  return self.frame.frame:active_frame():open_err(n)
end

function win:data()
  return self
end

function menu:data()
  return self.frame:win()
end

function mainmenu:data()
end

function mainmenu:output(n)
  n = n or "+Output"
  return self.frame:open_err(n)
end

local main = mainwin:new(mainmenu)

function main:killproc()
  for fr in main:for_win() do
    for w in fr:for_win() do
      w:killproc()
    end
  end
end

function mainwin:open_err(n)
  n = n or "+Errors"
  local w = self:win_by_name(n)
  if w then
    return w.frame:open_err(n)
  end
  return self:active_frame():open_err(n)
end

function mainwin:win_by_name(n)
  for fr in self:for_win() do
    local r, v = fr:win_by_name(n)
    if r then return r, v end
  end
end

function mainwin:file(n)
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

function mainwin:empty_frame()
  for f, k in self:for_win() do
    local nr = f:win_nr()
    if nr == 0 then
      return self:win(k)
    end
  end
end

function mainwin:active_frame()
  local i, min = 1, 10000
  for f, k in self:for_win() do
    local nr = f:win_nr()
    if nr < min then
      i = k
      min = nr
    end
  end
  return self:win(i)
end

local oldevents
local function prepare()
  screen:clear(16)
  gfx.border{ 0xde, 0xde, 0xde }
  sys.input(true) -- clear input
  oldevents = table.clone(sys.event_filter())
  gfx.win(256, 256)
end

local function resume()
  win:init(conf)
  main:geom(0, 0, scr.w, scr.h)
  gfx.border{ 0xde, 0xde, 0xde }
  mixer.done()
  mixer.init()
  sys.hidemouse(false)
  screen:nooffset()
  screen:noclip()
  sys.input(true) -- clear input
  sys.event_filter(oldevents)
end

function mainmenu.cmd:Run(t)
  if not t then return end
  prepare()
  sys.exec(t)
  sys.suspend()
  -- resumed
  resume()
end

function framemenu.cmd:Run(t)
  local w = self.frame:win()
  if not t and (not w or not w.buf:isfile()) then
    return
  end

  if not t then
    w:save()
  end

  prepare()
  sys.exec(t or w.buf.fname)
  sys.suspend()
  -- resumed
  resume(w)
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
      main:win(i):win().menu = b.menu
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

if #ARGS > 0 then
  mainmenu.cmd.Newcol(mainmenu)
  for i = #ARGS, 1, -1 do -- reverse order!
    main:win():file(ARGS[i])
  end
else
  if conf.nodump or not load_dump "red.dump" then
    mainmenu.cmd.Newcol(mainmenu)
    main:win():file("./")
  else
    conf.save_dump = true
  end
end

while not conf.stop do
  local r, v, a, b = sys.input()
  if r == 'quit' then
    mainmenu.cmd.Exit(mainmenu)
  elseif r == 'resized' or r == 'exposed' then
    win:init(conf)
    main:geom(0, 0, scr.w, scr.h)
  else
    main:event(r, v, a, b)
  end
  main:show()
  if conf.stop then break end
  gfx.flip(main:process() or 10, true)
end

mainmenu.cmd.Exit(mainmenu)
mixer.done()
-- print "Quit..."
