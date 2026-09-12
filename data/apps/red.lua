local win = require "red/win"
local frame = require "red/frame"
local proc = require "red/proc"
local shell = require "red/shell"
local uri = require "red/uri"
local conf = require "red/conf"
local win_keys = require "red/keys"

local presets = require "red/presets"
local dumper = require "dump"
local HISTFILE = DATADIR .. '/red.hist'

sys.title "red"

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
    fifo = false,
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
  conf.fifo = ops.fifo
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
  if fn:endswith ':' then
    table.remove(a, #a)
  end
  if #a > 1 and tonumber(a[#a]) then
    local pos = 0
    if #a > 2 and tonumber(a[#a-1]) then
      pos = tonumber(table.remove(a, #a))
    end
    local nr = tonumber(table.remove(a, #a))
    return table.concat(a, ':'), nr, pos
  end
  return fn, 0, 0
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
  table.insert(dir, 1, '..')
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
    return false, "Buffer is not writable file"
  end
  local trim = self:getconf 'trim_spaces'
  if trim then
    local nr, pos = self.buf:line_nr()
    self.buf:set(self.buf:gettext():gsub('[ \t]+\n', '\n'):gsub("[ \t\n]+$", "\n"))
    self.buf:toline(nr, false)
    local start = self.buf.cur
    for i = start, start + pos - 1 do
      if not self.buf.text[i] or self.buf.text[i] == '\n' then
        break
      end
      self.buf.cur = self.buf.cur + 1
    end
    self:dirty(true)
  end
  local r, e = self.buf:save_atomic()
  if r then
    self:nodirty()
  else
    self.frame:err(e)
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

function win:path(t, from)
  local to = self.cwd
  if not to then return t or './' end
  if t then
    if sys.is_absolute_path(t) then
      if not from then
        return t
      end
      to = sys.realpath(t)
    else
      to = sys.realpath(to .. '/' .. t)
    end
  end
  local abs = to
  to = to:split('/')
  from = sys.realpath(from or './')
  from = from:split('/')
  local p = ''
  local k = #from + 1
  for i = 1, #from do
    if from[i] ~= to[i] then
      k = i
      p = p .. string.rep('../', #from - i)
      p = p .. '..'
      break
    end
  end
  for i = k, #to do
    if p ~= '' then
      p = p .. '/'
    end
    p = p .. to[i]
  end
  if p == '' then return './' end
  -- relative and canonical paths may trade places
  if #abs < #p then
    return abs
  end
  return p
end

function win:getcwd()
  return sys.realpath(sys.dirname(self.frame:getfilename()))
end

function win:exec(t)
  t = t:unesc()

  -- command words work from the window body like from its menu:
  -- the window commands first, then the column menu commands
  local f = self.frame
  local i = f and f:find_win(self)
  if i and i > 0 then
    local a = t:strip():split(1)
    if self.cmd and self.cmd[a[1]] then
      self.cmd[a[1]](self, a[2])
      return true
    end
    local m = f:menu()
    if m and m.cmd and m.cmd[a[1]] then
      m.cmd[a[1]](self, a[2])
      return true
    end
  end

  if self:proc(t) then
    return true
  end

  local fr = self.frame:main()

  if self.frame:win_by_name(t) then
    return self.frame:file(t)
  end

  for _, u in ipairs(uri) do
    if t:find(u[1]) then
      print(string.format(u[2], t))
      proc['!'](self, string.format(u[2], t))
      return
    end
  end

  if self.buf:isdir() and sys.is_absolute_path(self.buf.fname) then
    t = sys.realpath(self.buf.fname .. t)
  else
    t = self:path(t)
  end

  local ff = filename_line(t)

  if not sys.isdir(ff) and fr:win_by_name(ff) then
    return fr:file(t)
  end

  if not sys.isdir(ff) then
    if not io.access(ff, "r") and not ff:startswith '+' then
      return
    end
  elseif self.buf:isdir() and not input.keydown 'alt' then
    self.cwd = sys.realpath(ff)
    self.buf.fname = dirpath(ff)
    self:set ""
    self:readdir(ff)
    self:cur(1)
    self.pos = 1
    self.frame:update(true)
    return
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

function menu:draw_scroller(color)
  if not self.x or not self.h or self.h == 0 then return end
  screen:clear(self.x, self.y, scr.spw, self.h, color)
  screen:rect(self.x, self.y,
    self.x + scr.spw - 1,
    self.y + self.h - 1, conf.fg)
end

function menu:scroller()
  local color
  if self.frame.stacked then
    -- stacked: the frame menu has its own palette color, ignore dirty
    color = conf.menu
  else
    color = self.frame:dirty() and
      self.frame:win():dirty() and
      conf.active or conf.button
  end
  self:draw_scroller(color)
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

function frame:file(f, pos, force)
  local fn, nr, col = filename_line(f)
  local dir = sys.isdir(fn)
  if dir then
    fn = dirpath(fn)
  end
  local b = not force and self:win_by_name(f)
  if b then -- already opened
    self:push_win(b)
    self:win():toline(nr, col)
    return b
  end

  b = win:new(fn)
  b.menu = self:menu().buf:gettext() -- clone menu
  b.conf = presets.get(fn) or {}
  if dir then
    b.cwd = sys.realpath(fn)
    b:set ""
    b:readdir(fn)
    b:cur(1)
  elseif not fn:startswith '+' then
    b.cwd = sys.realpath(sys.dirname(fn))
    b:file(fn)
    if nr == 0 and b:histfile_get() then
      self:push_win(b)
      self:win():visible()
      return b
    end
  end
  if pos then
    self:add_win(b, pos)
    self:update(true, true)
    self:refresh()
  else
    self:push_win(b)
  end
  b:toline(nr, col)
  return b
end

-- file name typed in the tag part of a menu text (before |)
function frame.menu_filename(text)
  local fn = text:split('|', 1)[1]
  if fn then
    fn = (fn:escsplit()[1] or ''):strip()
  end
  return fn
end

function frame:getfilename()
  if not self.frame then
    return "./"
  end
  local fn = frame.menu_filename(self:menu().buf:gettext())
  return fn and not fn:empty() and fn
end

-- rename the window according to the file name typed in its menu
function frame:rename_from_menu(w, text)
  local fn = frame.menu_filename(text)
  if fn and not fn:empty() and fn ~= w.buf.fname then
    self:rename_win(w, fn)
  end
end

function frame:rename_win(w, fn)
  if not w or not fn or fn == w.buf.fname then
    return
  end
  while self.frame:win_by_name(fn) do
    fn = '~' .. fn
  end
  w.buf.fname = fn
  w.conf = presets.get(fn) or {}
end

function frame:show()
  if scr.grab then return end
  if self.stacked then
    self:menu():show()
    for i = 2, #self.childs do
      local c = self.childs[i]
      local cm = self:cmd_menu(c)
      if cm then cm:show() end
      c:show()
    end
    return
  end
  for _, v in ipairs(self.childs) do
    if v:show() then
      break
    end
  end
end

function frame:sort()
  self.prev_win = nil
  table.sort(self.childs, function(a, b)
    if not a.buf.fname then return true end
    if not b.buf.fname then return false end
    return a.buf.fname < b.buf.fname
  end)
  self:update(true, true)
  self:refresh()
end

function frame:update(force, pop)
  if self.stacked then
    self:update_menu(nil, false)
    for c in self:for_win() do
      self:update_menu(c, true)
    end
    return
  end
  if pop then
    self:menu():set(self:win() and self:win().menu or conf.emptymenu)
  end
  local w = self:win()
  self:update_menu(w, not force)
  if w then
    w.menu = self:menu():gettext()
    if force then
      w.cwd = w.cwd or w:getcwd()
    end
  end
end

-- command line of a menu: the tail after | or the default one
function frame.menu_cmdline(m)
  local tail = frame.menu_tail(m:gettext())
  if not tail or tail:strip() == '|' then
    return conf.emptymenu
  end
  return tail
end

-- desired text of the menu which holds the command line of window w;
-- without w it is the frame (column) menu
function frame:menu_text(w)
  local m = w and self:cmd_menu(w) or self:menu()
  local t
  if self.stacked then
    if not w then
      t = 'Del '
    else
      t = ''
      if w.buf.fname then
        t = w.buf.fname:esc() .. ' '
      end
      t = t .. frame.win_words(w)
    end
  else
    t = ''
    for c in self:for_win() do
      t = t .. c.buf.fname:esc() .. ' '
    end
    if w then
      t = t .. frame.win_words(w)
    end
    if self.frame:win_nr() > 1 then
      t = t .. 'Del ' -- Delcol
    end
  end
  return t .. frame.menu_cmdline(m)
end

-- rebuild the menu which holds the command line of window w, taking
-- the file name typed in it into account when `rename` is set
function frame:update_menu(w, rename)
  local m = w and self:cmd_menu(w) or self:menu()
  if rename and w then
    self:rename_from_menu(w, m:gettext())
  end
  local text = self:menu_text(w)
  if m:gettext() ~= text then
    m:set_keep(text, m:getsel())
  end
end

-- command words of one window in a menu: "[Put ]Close Get [cmdline]"
function frame.win_words(w)
  local t = ''
  if w:dirty() and w.buf:isfile() then
    t = t .. 'Put '
  end
  t = t .. 'Close Get '
  if w.cmdline then
    t = t .. w.cmdline .. ' '
  end
  return t
end

local framemenu = menu:new()
framemenu.cmd = {}

-- start a frame square drag: resize with LMB, move the active window of
-- the column with RMB, toggle stacking with MMB; returns true if started
function framemenu:press(v, a, b)
  local x, y = a - self.x, b - self.y
  if x < 0 or x >= scr.spw or y < 0 or y >= self.h then
    return
  end
  local f = self.frame
  if v == 'left' then
    f.press = { menu = self, kind = 'resize', x = a, y = b }
  elseif v == 'right' then
    f.press = { menu = self, kind = 'move', x = a, y = b }
  elseif v == 'middle' then
    f.press = { menu = self, kind = 'toggle', x = a, y = b }
  else
    return
  end
  return true
end

function framemenu:event(r, v, a, b)
  if r == 'mousedown' and self:press(v, a, b) then
    return true
  end
  return menu.event(self, r, v, a, b)
end

function framemenu:new(...)
  local r = menu.new(self, ...)
  r:set(conf.emptymenu)
  return r
end

-- window menu in stacked mode (one per window); `self.win` is its window
local win_menu = menu:new()
win_menu.cmd = framemenu.cmd

function win_menu:scroller()
  self:draw_scroller(self.win and self.win:dirty() and
    conf.active or conf.button)
end

-- press on the menu bar: the square starts a size press, the rest of the
-- menu starts a move press
function win_menu:press(v, a, b)
  local x, y = a - self.x, b - self.y
  if x < 0 or x >= self.w or y < 0 or y >= self.h then
    return
  end
  local f = self.frame
  if v == 'left' and x < scr.spw then
    f.press = { menu = self, win = self.win, kind = 'resize', x = a, y = b }
  elseif v == 'right' then
    f.press = { menu = self, win = self.win, kind = 'move', x = a, y = b }
  end
end

function win_menu:event(r, v, a, b)
  if r == 'mousedown' and self.frame.stacked then
    self:press(v, a, b)
  end
  return menu.event(self, r, v, a, b)
end

-- continue a press: resize follows the mouse, move shows the cursor and
-- drops the window on release
function frame:press_event(r, v, a, b)
  local p = self.press
  local d = conf.drag_delta * SCALE
  if r == 'mouseup' then
    self.press = nil
    if p.kind == 'resize' then
      scr.grab = false
      return p.active
    end
    p.menu:show_cursor()
    if p.kind == 'toggle' then -- click = toggle
      if math.abs(a - p.x) < d and math.abs(b - p.y) < d then
        self:stacked_toggle()
      end
      return true
    end
    if p.active then
      if p.win then
        self.frame:move_win(self, p.win, a, b)
      else -- the frame square moves the active window of the column
        self.frame:move(math.max(scr.spw, a), b, self)
      end
      return true
    end
    -- the frame square consumes the release, the window menu lets the
    -- menu handle it (right click = search)
    return not p.win
  end
  if r ~= 'mousemotion' then
    return
  end
  local _, _, mb = input.mouse()
  if p.kind == 'toggle' then
    return true
  end
  if p.kind == 'move' then
    if not mb.right then
      p.menu:show_cursor()
      self.press = nil
      return true
    end
    if not p.active then
      if math.abs(v - p.x) < d and math.abs(a - p.y) < d then
        return true
      end
      p.active = true
    end
    p.menu:show_cursor(v, a, conf.move_cursor)
    return true
  end
  if not (mb.left and not mb.right) then
    self.press = nil
    scr.grab = false
    return
  end
  if not p.active then
    if math.abs(v - p.x) < d and math.abs(a - p.y) < d then
      return
    end
    p.active = true
    p.last_x, p.last_y = p.x, p.y
    p.menu.autoscroll_on = false
    scr.grab = true
  end
  local dx, dy = v - p.last_x, a - p.last_y
  p.last_x, p.last_y = v, a
  if dx ~= 0 then
    self.frame:resize_col(self, dx)
  end
  if p.win and dy ~= 0 and (self:find_win(p.win) or 0) > 1 then
    self:resize_win(p.win, dy)
  end
  return true
end

function frame:new_win_menu(w)
  local m = win_menu:new()
  m.frame = self
  m.win = w
  -- start from the command line remembered for this window
  m:set(frame.menu_tail(w.menu) or conf.emptymenu)
  return m
end

function framemenu.cmd:Del() -- Delcol
  local main = self.frame:main()
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
  self.frame:main():refresh()
end

function framemenu.cmd:Wrap()
  local w = self:data()
  if not w then return end
  w.conf.wrap = not w.conf.wrap
  self.frame:update()
end

function framemenu.cmd:Tab(nr)
  local w = self:data()
  if not w then return end
  if tonumber(nr) then
    w.conf.ts = math.max(1, math.min(nr, 8))
    self.frame:update()
  end
  w.conf.spaces_tab = false
end

function framemenu.cmd:Spaces()
  local w = self:data()
  if not w then return end
  w.conf.spaces_tab = true
end

function framemenu.cmd:Syntax()
  local w = self:data()
  if not w then return end
  if w.syntax then
    w.conf.syntax = w.syntax
    w.syntax = nil
  else
    w.syntax = w.conf.syntax
    w.conf.syntax = false
  end
end

function framemenu.cmd:Sort()
  self.frame:sort()
end

function framemenu.cmd:Put()
  local b = self:data()
  if not b then
    return
  end
  local f = b.buf.fname or (self.frame:getfilename())
  if f then
    local r, e = b:save()
    if not r then
      self.frame:err(e)
    end
  end
  self.frame:update()
end

-- base window commands to control output following; the menu word shows
-- the action which is available now
local function set_scroll(s, on)
  s.scroll_mode = on
  if s.cmdline == 'Scroll' or s.cmdline == 'Noscroll' then
    s.cmdline = on and 'Noscroll' or 'Scroll'
    s.frame:update()
  end
  return true
end

function win.cmd.Scroll(s)
  return set_scroll(s, true)
end

function win.cmd.Noscroll(s)
  return set_scroll(s, false)
end

function win:Get()
  local f = self.buf.fname
  if not f then return end
  if sys.isdir(f) then
    self:set ""
    self:readdir(f)
    self:cur(1)
  elseif self.buf:isfile() then
    local r, e = self.buf:load()
    if not r then
      self.frame:err(e)
      return
    end
    self:dirty(self.buf:dirty())
    self:cur(self:cur())
  end
end

function framemenu.cmd:Get()
  local b = self:data()
  if not b then return end
  b:Get()
  self.frame:update()
end

function framemenu.cmd:Close()
  self.frame:close_win(self:data())
end

function framemenu.cmd:New(w)
  local f = self.frame
  local nf = w or f.frame:getnewfile()
  -- for a window menu insert below its window, for a body below the
  -- window where the command was typed
  local k = f.stacked and f:find_win(self.win or self)
  if k and k > 0 then
    f:file(nf, k + 1)
  else
    f:file(nf)
  end
  f:refresh()
end

local mainmenu = menu:new()
mainmenu.cmd = {}

mainmenu.buf:set 'Help GetAll PutAll Dump Exit Sort New'

function mainmenu:scroller(click)
  if click then
    for w in self.frame:for_win() do
      local ww = w:dirty()
      if ww and ww.frame:win() ~= ww then
        ww.frame:push_win(ww)
        break
      end
    end
  end
  self:draw_scroller(self.frame:dirty() and conf.active or conf.button)
end

function mainmenu.cmd:Dump()
  local d = {}
  d.menu = self.buf:gettext()
  for f in self.frame:for_win() do
    local c = {
      menu = f:menu().buf:gettext(),
      stacked = f.stacked,
      frac = f.frac,
      stacked_cmdline = f.stacked_cmdline,
    }
    for w in f:for_win() do
      table.insert(c, {
        fname = string.format("%s", w.buf.fname),
        line = w.buf:line_nr(),
        text = w.buf:gettext(),
        menu = w.menu,
        cwd = w.cwd,
        cmdline = w.cmdline,
        frac = w.frac,
        shell = w.shell and true,
        output_pos = w.shell and w.output_pos,
        hist = w.shell and w.shell.hist,
        scroll = w.scroll_mode,
      })
    end
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

function mainmenu.cmd:Sort()
  for f in self.frame:for_win() do
    f:sort()
  end
end

local help_text = [==[```
           ___  _______
          / _ \/ __/ _ \
         / , _/ _// // /
        /_/|_/___/____/

       RED - Rein EDitor
       by Peter Kosyh (2023-2026)
       https://hugeping.ru
```

# SYNOPSYS

  rein [-platform-nojoystick] [-platform-nosound] [-platform-xclip[-only]]
      red [-fs <font size>] [-nodump] [-confdir <dir>]

# KEYS

- esc           - cut, select last typed block
- ctrl-esc      - select all text
- ctrl-s        - Save (Put) current buffer
- ctrl-w        - Close current buffer
- ctrl-o        - Previous buffer
- ctrl-x,c,v    - cut, copy, paste
- alt-w         - smart selection
- ctrl-a,e      - line start, end
- home,end      - line start, end
- ctrl-home,end - first line, last line
- ctrl-k        - kill to eol
- ctrl-z        - undo
- ctrl-y        - redo
- shift-arrows  - select
- insert        - toggle overwrite mode
- del,backspace - delete symbol right/left
- ctrl-b        - insert current line in menu (bookmark)
- alt-b         - insert current fname:line in mainmenu (global bookmark)
- ctrl-f        - completion path
- alt-f         - completion via 'global -t -c'

# MOUSE

Plan9 acme like mouse chording and actions

To move file buffer between columns use mouse 2nd button drag&drop of menu button.

- right mb     - search
- alt+rmb      - search back
- middle mb    - exec command or open

# BUILT-IN COMMANDS

- gfind lua-rexp      - find rexp in text (multilines)
- gfind /lua-rexp/
- gsub /lua-rexp/

- find lua-rexp       - find rexp in text (by lines)
- find /lua-rexp/
- sub /lua-rexp/

- sub /lua-rexp/b/    - change rexp to b (by lines)
- gsub /lua-rexp/b/   - change rexp to b (multilines)

> Note:
> You can use ":" delimiter instead of "/" in find, gfind, sub, gsub.

- !cmd                - run cmd
- <cmd                - run cmd and get output
- @cmd                - run cmd <text> and get output

> Unix only:
> - >cmd                - cat <text> | cmd > output
> - |cmd                - cat <text> | cmd > edit

- fmt [width]         - fmt text by width
- par                 - remove newlines and extra spaces
- cat <file>          - insert file into the cursor
- dos2unix            - remove \r
- i+/i-               - indent inc/dec
- Run <prog>          - run prog in rein
- sprited             - run sprited (rein)
- voiced              - run voiced (rein)
- Line                - get current line in buffer
- Codepoint           - get codepoint of the sym
- Clear               - clear window
- Sort                - sort buffers by names
- Tab [nr]            - tab on for current bufferr
- Wrap                - wrap text on/off
- Spaces              - spaces tab mode
- Syntax              - toggle syntax hl
- dump                - hex-dump
- win                 - pseudo acme win-shell

> win-shell notes (for Unix only):
>   esc          - close input
>   delete       - try to kill programm
>   ctrl-up/down - history
>   ls/cd/pwd    - built-in commands

# ARGUMENTS

* -platform-xclip - use X11 clipboard
* -platform-nojoystick - no joystick, start faster!
* -platform-nosound - no sound, start faster!
* -nodump - do not load red.dump
* -fifo <fifo> - Unix only, create fifo and open files from it

* -confdir <directory>

You can put files in confdir:

- conf.lua - changes in config
- presets.lua - presets for files
- uri.lua - uri handlers
- keys.lua - keybindings
- proc.lua - procedures

# EXAMPLE USAGE

```
--- [~/.red/conf.lua] ---
  return {
    syntax = true,
    histfile = true,
  }
-------------------------

--- [~/bin/red] ---------
  #!/bin/sh
  exec ~/Devel/rein/rein -platform-xclip -platform-nosound -platform-nojoysticks red -fs 14 -confdir ~/.red "$@" 2>/dev/null >/dev/null &
-------------------------

$ red file1.txt file2.txt ...
```

Happy hacking!
]==]

function mainmenu.cmd:Help()
  local w = self.frame:open_err("+Help.md")
  w:clear()
  w:printf("%s", help_text)
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

function mainmenu.cmd:New() -- Newcol
  self.frame:add(frame:new(framemenu:new()))
  for v in self.frame:for_win() do
    v:update()
  end
  self.frame:refresh()
end

function mainmenu.cmd:Syntax()
  conf.syntax = not conf.syntax
end

local mainwin = frame:new()

function mainwin:update()
end

function mainwin:getnewfile()
  local max = 0
  local new = conf.new_prefix or 'new'
  for f in self:for_win() do
    for w in f:for_win() do
      if w.buf and w.buf.fname and
        w.buf.fname:startswith(new) then
        local nr = tonumber(w.buf.fname:sub(new:len()+1))
        if nr and nr > max then
          max = nr
        end
      end
    end
  end
  return string.format(new..'%d', max + 1)
end

-- drag the border between column c and the previous one by dx pixels
function mainwin:resize_col(c, dx)
  self:frac_norm()
  self:resize_frac(c, dx, self.w, scr.spw)
end

function mainwin:hgeom(x, y, w, h)
  local menu = self:menu()
  local pos = menu:bottom()
  h = h - pos
  self:frac_norm()
  local n = self:win_nr()
  local cx, used = x, 0
  for c, i in self:for_win() do
    local cw
    if i == n then
      cw = w - used
    else
      cw = math.floor(w * (c.frac or (1 / n)))
      used = used + cw
    end
    if cw < scr.spw then cw = scr.spw end
    c:geom(cx, y + pos, cw, h)
    cx = cx + cw
  end
end

function mainwin:geom(x, y, w, h)
  local menu = self:menu()
  self.x, self.y, self.w, self.h = x, y, w, h
  menu:geom(x, y, w, 0)
  menu:geom(x, y, w, menu:realheight())
  menu.pos = math.max(0, menu.pos)
  menu.pos = math.min(menu.pos, #menu.buf.text)

  local pos = menu:bottom()

  if self:win_nr() == 0 then
    screen:clear(x, pos, w, h - pos, conf.void_bg)
    return
  end
  return self:hgeom(x, y, w, h)
end

-- move the active window of frame w to the column under (x, y)
function mainwin:move(x, y, w)
  local b = w:win()
  if not b then return end
  return self:move_win(w, b, x, y)
end

function mainwin:frame_at(x, y)
  for c in self:for_win() do
    if x >= c.x and x < c.x + c.w and
      y >= c.y and y < c.y + c.h then
      return c
    end
  end
end

function mainwin:move_win(src, w, x, y)
  local dst = self:frame_at(x, y)
  if not dst or not w then return end
  if dst ~= src and w.buf.fname and dst:win_by_name(w.buf.fname) then
    return
  end
  local cur = src:find_win(w)
  if not cur then return end
  local idx = dst:win_at(y)
  if dst == src then
    if idx > cur then idx = idx - 1 end
    if idx == cur then return end
  end
  src:del_win(cur)
  dst:add_win(w, idx)
  src:update(true, true)
  if dst ~= src then
    dst:update(true, true)
  end
  self:refresh()
  return true
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

function win:output(n)
  if n then
    return menu.output(self, n)
  end
  return self
end

function menu:output(n)
  local cwd = self:getcwd()
  n = n or "+Output"
  local w = self.frame:main():win_by_name(n)
  if w then
    w = w.frame:open_err(n)
    w.cwd = cwd
    return w
  end
  w = self.frame:open_err(n)
  w.cwd = cwd
  return w
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

function win:Run(cmd, ...)
  local state = sys.prepare()
  sys.reset()
  sys.exec(cmd, ...)
  sys.suspend()
  -- resumed
  sys.resume(state)
  win:init(conf)
  main:geom(0, 0, scr.w, scr.h)
end

function mainmenu.cmd:Run(t)
  if not t then return end
  self:Run(t)
end

function framemenu.cmd:Run(t)
  local w = self:data()
  if not t and (not w or not w.buf:isfile()) then
    return
  end
  if not t then
    w:save()
  end
  self:Run(t or w.buf.fname)
end

local function select_sect(w, name)
  if w.buf:issel() then
    return w.buf:getseltext():strip()
  end

  local c = w:cur(1)

  if not w:text_match(function(text)
      local pat = string.format("local __%s__ = %%[%%[[^%%]]*%%]%%]", name)
      return text:find(pat)
    end) then
    return
  end
  w:cur(c)
  local t = w.buf:getseltext()
  local _
  _, _, t = t:find("^[^%[]+%[%[(.*)%]%]$")
  t = t and t:strip()
  return t
end

local function write_sect(w, name, fname)
  io.file(fname, select_sect(w, name) or '')
end

local function input_sect(w, name, text)
  text = text:strip()
  if not text or text:empty() then return end
  local old
  select_sect(w, name)
  local t = string.format("local __%s__ = [[\n%s\n]]", name, text)
  if not w.buf:issel() then
    old = w:cur()
    w.buf.cur = #w.buf.text
    w:input '\n'
  end
  w.buf:input(t)
  if old then w:cur(old) end
end

local function read_sect(w, name, fname)
  input_sect(w, name, io.file(fname))
end

function framemenu.cmd.voiced(w)
  local data = w:data()
  if not data then return end

  data.buf:resetsel()

  local fname = 'red-rein-data'

  write_sect(data, "voices", fname..'.syn')
  data.buf:resetsel()
  write_sect(data, "songs", fname..'.sng')
  data.buf:resetsel()

  data:Run('voiced', fname..'.syn', fname..'.sng')

  read_sect(data, "voices", fname..'.syn')
  data.buf:resetsel()
  read_sect(data, "songs", fname..'.sng')
  data.buf:resetsel()

  os.remove(fname..'.syn')
  os.remove(fname..'.sng')
end

function framemenu.cmd.sprited(w)
  local data = w:data()
  if not data then return end
  local sel = data.buf:issel()
  local fname = 'red-rein-data'

  write_sect(data, "spr", fname .. '.spr')
  if not sel then
    data.buf:resetsel()
    write_sect(data, "map", fname .. '.map')
    data.buf:resetsel()
  end
  data:Run('sprited', fname..'.spr')

  read_sect(data, "spr", fname..'.spr')
  if not sel then
    data.buf:resetsel()
    read_sect(data, "map", fname..'.map')
    data.buf:resetsel()
  end
  os.remove(fname..'.spr')
  os.remove(fname..'.map')
end

main:geom(0, 0, scr.w, scr.h)

local function load_dump(f)
  local d = dumper.load(f)
  if not d then return end
  for i, v in ipairs(d) do
    mainmenu.cmd.New(mainmenu) -- Newcol
    local fr = main:win(i)
    local wins = {}
    for idx, b in ipairs(v) do
      -- force: a dump may hold two windows with the same relative name
      local w = fr:file(b.fname, idx, true)
      wins[idx] = w
      if w then
        if b.text then
          w:set(b.text)
          w:dirty(w.buf:dirty())
        end
        if b.line then
          w:toline(b.line, false)
        end
      end
    end
    for idx, b in ipairs(v) do
      local w = wins[idx]
      if w then
        w.menu = b.menu
        w.cwd = b.cwd
        w.cmdline = b.cmdline
        w.frac = b.frac
        if b.shell then
          shell.win(w)
          w.cmdline = b.cmdline or w.cmdline
          w.shell.hist = b.hist or {}
          w.output_pos = b.output_pos
          w:cur(#w.buf.text + 1)
        end
        if b.scroll ~= nil then
          w.scroll_mode = b.scroll
        end
      end
    end
    if v.menu then
      fr:menu().buf:set(v.menu)
    end
    fr.stacked = v.stacked
    fr.frac = v.frac
    fr.stacked_cmdline = v.stacked_cmdline
    fr:update(true, true)
  end
  if d.menu then
    main:menu():set(d.menu)
  end
  main:refresh()
  -- geometry is only final now; put every viewport on its cursor line
  for fr in main:for_win() do
    for w in fr:for_win() do
      w:visible()
    end
  end
  return true
end

if #ARGS > 0 then
  mainmenu.cmd.New(mainmenu) -- Newcol
  for i = #ARGS, 1, -1 do -- reverse order!
    main:win():file(ARGS[i])
  end
else
  if conf.nodump or not load_dump "red.dump" then
    mainmenu.cmd.New(mainmenu) -- Newcol
    main:win():file("./")
  else
    conf.save_dump = true
  end
end

sys.event_filter().wake = true -- wake on thread write

local fifo
if conf.fifo and PLATFORM ~= 'Windows' then
  os.remove(conf.fifo)
  if os.execute("mkfifo "..conf.fifo) then
    print("Listen fifo: "..conf.fifo)
    fifo = thread.start(function()
      local name = thread:read()
      local run = true
      while run do
        local f = io.open(name, "r")
        if not f then
          print("Cant open fifo on read")
          break
        end
        for l in f:lines() do
          if l == 'quit' then
            run = false
            break
          end
          thread:write(l)
        end
        f:close()
      end
      thread:write '\1quit'
    end)
  end
  fifo:write(conf.fifo)
end

while not conf.stop do
  local r, v, a, b
  if fifo and fifo:poll() then
    local l = fifo:read()
    if l == '\1quit' then
      fifo = false
    else
      main:win():file(l)
    end
  end
  repeat
    r, v, a, b = sys.input()
  until r ~= 'wake'
  if r == 'quit' then
    mainmenu.cmd.Exit(mainmenu)
  elseif r == 'resized' or r == 'exposed' then
    win:init(conf)
    main:geom(0, 0, scr.w, scr.h)
  else
    main:event(r, v, a, b)
  end
  -- safety net: if a mouse-up got lost, release the grab so frame:show()
  -- keeps redrawing (also covers the frame menu resizer)
  if scr.grab and r ~= 'mousedown' and r ~= 'mousemotion' then
    local _, _, mb = input.mouse()
    if not (mb.left or mb.right or mb.middle) then
      scr.grab = false
    end
  end
  main:show()
  if conf.stop then break end
  gfx.flip(main:process() or 10, true)
end

mainmenu.cmd.Exit(mainmenu)

if fifo then
  io.file(conf.fifo, "quit\n")
  os.remove(conf.fifo)
end

mixer.done()
-- print "Quit..."
