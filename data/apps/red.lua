local win = require "red/win"
local frame = require "red/frame"
local proc = require "red/proc"
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
    return
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
    --self:visible()
  end
  local r, e = self.buf:save()
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
  return p
end

function win:getcwd()
  return sys.realpath(sys.dirname(self.frame:getfilename()))
end

function win:exec(t)
  t = t:unesc()

  if self:proc(t) then
    return true
  end

  local fr = self.frame.frame and self.frame.frame or self.frame

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
    local f = io.open(ff, "r")
    if not f then
      return
    end
    f:close()
  elseif self.buf:isdir() then
    self.cwd = sys.realpath(ff)
    self.buf.fname = (ff .. '/'):gsub("/+", "/")
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
  local fn, nr, col = filename_line(f)
  local dir = sys.isdir(fn)
  if dir then
    fn = dirpath(fn)
  end
  local b = self:win_by_name(f)
  if b then -- already opened
    self:push_win(b)
    self:win():toline(nr, col)
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
  self:win():toline(nr, col)
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
    if self:win().cmdline then
      t = t .. self:win().cmdline .. ' '
    end
  end
  if self.frame:win_nr() > 1 then
    t = t .. 'Del ' -- Delcol
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
    if force then
      self:win().cwd = self:win().cwd or self:win():getcwd()
    end
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
        if self.frame.frame.vertical then
          local mh = self.frame.frame:menu().h
          self.frame.posy = math.min(math.max(a - mh, self.h),
            self.frame.frame.h - mh - self.h)
        else
          self.frame.posx = math.min(math.max(scr.spw, v),
            self.frame.frame.w - scr.spw)
        end
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
        if self.frame.frame.vertical then
          local mh = self.frame.frame:menu().h
          self.frame.posy = math.min(math.max(b - mh, self.h),
            self.frame.frame.h - mh - self.h)
        else
          self.frame.posx = math.min(math.max(scr.spw, a),
            self.frame.frame.w - scr.spw)
        end
        self.frame.frame:refresh()
        return true
      elseif v == 'right' then -- move
        self.frame.frame:move(math.max(scr.spw, a),
          b, self.frame)
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

function framemenu.cmd:Del() -- Delcol
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

function framemenu.cmd:Wrap()
  self.frame:win().conf.wrap = not self.frame:win().conf.wrap
  self.frame:update()
end

function framemenu.cmd:Tab(nr)
  if tonumber(nr) then
    self.frame:win().conf.ts = math.max(1, math.min(nr, 8))
    self.frame:update()
  end
  self.frame:win().conf.spaces_tab = false
end

function framemenu.cmd:Spaces()
  self.frame:win().conf.spaces_tab = true
end

function framemenu.cmd:Syntax()
  local w = self.frame:win()
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
  print("0")
  local d = self.frame.frame:getnewfile()
  print("d = ", d)
  self.frame:file(d)
  print("2")
  self.frame:refresh()
end

local mainmenu = menu:new()
mainmenu.cmd = {}

mainmenu.buf:set 'Help GetAll PutAll Dump Exit Horizont Sort New'

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
      b.cwd = w.cwd
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

function mainmenu.cmd:Sort()
  for f in self.frame:for_win() do
    f:sort()
  end
end

function mainmenu.cmd:Help()
  local w = self.frame:open_err("+Help")
  w.conf.wrap = true
  w:clear()
  w:printf([==[
           ___  _______
          / _ \/ __/ _ \
         / , _/ _// // /
        /_/|_/___/____/

       RED - Rein EDitor
       by Peter Kosyh (2023-2024)
       https://hugeping.ru

Arguments:
  rein [-platform-nojoystick] [-platform-nosound] [-platform-xclip[-only]]
      red [-fs <font size>] [-nodump] [-confdir <dir>]

Keys:
  esc           - cut, select last typed block
  ctrl-esc      - select all text
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
  ctrl-y        - redo
  shift-arrows  - select
  insert        - toggle overwrite mode
  del,backspace - delete symbol right/left
  ctrl-b        - insert current line in menu (bookmark)

Mouse:
  Plan9 acme like mouse chording and actions

  To move file buffer between columns use mouse 2nd button drag&drop of menu button.

  right mb     - search
  alt+rmb      - search back
  middle mb    - exec command or open

Some built-in commands:

  gfind lua-rexp      - find rexp in text (multilines)
  gfind /lua-rexp/
  gsub /lua-rexp/

  find lua-rexp       - find rexp in text (by lines)
  find /lua-rexp/
  sub /lua-rexp/

  sub /lua-rexp/b/    - change rexp to b (by lines)
  gsub /lua-rexp/b/   - change rexp to b (multilines)

Note:
  You can use ":" delimiter instead of "/" in find, gfind, sub, gsub.

  !cmd                - run cmd
  <cmd                - run cmd and get output
  @cmd                - run cmd <text> and get output
]==])
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
  sprited             - run sprited (rein)
  voiced              - run voiced (rein)
  Line                - get current line in buffer
  Codepoint           - get codepoint of the sym
  Clear               - clear window
  Sort                - sort buffers by names
  Tab [nr]            - tab on for current bufferr
  Wrap                - wrap text on/off
  Spaces              - spaces tab mode
  Syntax              - toggle syntax hl
  dump                - hex-dump
  win                 - pseudo acme win

    ** win notes **
    In Unix systems stdin is available.
    esc          - close input
    delete       - try to kill programm
    ctrl-up/down - history
    ls/cd/pwd    - built-in commands

Arguments:
  -platform-xclip - use X11 clipboard
  -platform-nojoystick - no joystick, start faster!
  -platform-nosound - no sound, start faster!
  -nodump - do not load red.dump
  -fifo <fifo> - Unix only, create fifo and open files from it

-confdir <directory>
  You can put files in confdir:
    conf.lua - changes in config
    presets.lua - presets for files
    uri.lua - uri handlers
    keys.lua - keybindings
    proc.lua - procedures

Example usage:

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

Happy hacking!
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

function mainmenu.cmd:Horizont()
  self.frame.vertical = true
  self.buf:set(self.buf:gettext():gsub("Horizont", "Vertical"))
  self.frame:refresh()
end

function mainmenu.cmd:Vertical()
  self.frame.vertical = false
  self.buf:set(self.buf:gettext():gsub("Vertical", "Horizont"))
  self.frame:refresh()
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

function mainwin:vgeom(x, y, w, h)
  local scale = 1

  local menu = self:menu()
  local pos = menu:bottom()
  local dh = math.floor((h - pos) / self:win_nr())
  local lasty = 0
  for c, i in self:for_win() do
    if c.posy and c.posy <= (h - pos) then
      c.posy = math.floor(c.posy * scale) else
      c.posy = y + (i-1)*dh
    end
    c.posy = c.posy or c.y
    if c.posy < lasty then
      c.posy = lasty
    end
    c:menu():geom(x, y + pos + c.posy, w, 0)
    lasty = lasty + c:menu().h
  end
  table.sort(self.childs, function(a, b)
    return (a.posy or -1) < (b.posy or -1)
  end)
  for c, i in self:for_win() do
    local r = self:win(i+1) or { posy = self.h - pos }
    if i == 1 then
      c.posy = 0
    end
    local d = r.posy - c.posy
    if i ~= self:win_nr() then
      if d < c:menu().h then
        r.posy, c.posy = c.posy - c:menu().h, r.posy + r:menu().h
        d = r:menu().h
      end
    end
    c:geom(x, y + pos + c.posy, w, d)
  end
end

function mainwin:hgeom(x, y, w, h)
  local scale = 1

  local menu = self:menu()
  local pos = menu:bottom()

  local dw = math.floor(w / self:win_nr())
  h = h - pos
  for c, i in self:for_win() do
    if c.posx and (c.posx <= w - scr.spw) then
      c.posx = math.floor(c.posx * scale) else
      c.posx = x + (i-1)*dw
    end
    c.posx = c.posx or c.x
  end
  table.sort(self.childs, function(a, b) return (a.posx or -1) < (b.posx or -1) end)
  for c, i in self:for_win() do
    local r = self:win(i+1) or { posx = self.w }
    if i == 1 then
      c.posx = 0
    end
    local d = r.posx - c.posx
    if d < scr.spw then
      r.posx, c.posx = c.posx - scr.spw, r.posx + scr.spw
      d = r.w
    end
    c:geom(c.posx, y + pos, d, h)
  end
end

function mainwin:geom(x, y, w, h)
  local menu = self:menu()
--  if self.w then
--    scale = w / self.w
--  end
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
  if self.vertical then
    return self:vgeom(x, y, w, h)
  else
    return self:hgeom(x, y, w, h)
  end
end

function mainwin:move(x, y, w)
  for c in self:for_win() do
    if x >= c.x and x < c.x + c.w and
      y >= c.y and y < c.y + c.h then -- move it!
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
  local cwd = self:getcwd()
  n = n or "+Output"
  local w = self.frame.frame:win_by_name(n)
  if w then
    w = w.frame:open_err(n)
    w.cwd = cwd
    return w
  end
  w = self.frame.frame:active_frame():open_err(n)
  w.cwd = cwd
  return w
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
main.vertical = false

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
  local w = self.frame:win()
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
  t = string.format("local __%s__ = [[\n%s\n]]", name, text)
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
  local data = w:winmenu()
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
  local data = w:winmenu()
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
    for _, b in ipairs(v) do
      fr:file(b.fname)
      if b.text then
        local ww = main:win(i):win()
        ww:set(b.text)
        ww:dirty(ww.buf:dirty())
      end
      if b.line then
        fr:win():toline(b.line, false)
      end
      fr:win().menu = b.menu
      fr:win().cwd = b.cwd
    end
    if v.menu then
      fr:menu().buf:set(v.menu)
    end
  end
  if d.menu then
    main:menu():set(d.menu)
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
    end)
  end
  fifo:write(conf.fifo)
end

while not conf.stop do
  local r, v, a, b
  if fifo and fifo:poll() then
    main:win():file(fifo:read())
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
