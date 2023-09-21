local buf = require "red/buf"

local win = {
  cmd = {},
}

local conf

local scr = {
  w = 0,
  h = 0,
  spw = 0,
  sph = 0,
  font = false,
}

local delim_exec = {
  [" "] = true,
  ["\n"] = true,
}

function scr:init()
  sys.event_filter().resized = true
  local w, h = sys.window_size()
  local fn = conf.font
  local sz = math.round(conf.font_sz * SCALE)
  gfx.win(w - sz, h - sz,
    scr.font or gfx.font(fn, sz))
  self.font = font
  self.w, scr.h = screen:size()
  self.spw, scr.sph = font:size " "
  self.glyphs = self.glyphs or {}
  gfx.border(conf.brd)
end

function scr:glyph(sym, col)
  if sym == '\t' or sym == '\n' or sym == false then
    return
  end
  local c = self.glyphs[col]
  if not c then
    c = {}
    self.glyphs[col] = c
  end
  local g = c[sym]
  if g then
    return g
  end
  local vs = sym
  if vs == '\r' then vs = conf.cr_sym end
  g = self.font:text(vs) or
    self.font:text(conf.unknown_sym, col)
  local w, h = g:size()
  if w > self.spw or h > self.sph then
    g = self.font:text(conf.unknown_sym, col)
  end
  c[sym] = g
  return g
end

function win:init(cfg)
  conf = cfg
  scr:init()
  self.scr = scr
end

function win:new(fname)
  local w = { buf = buf:new(fname), glyphs = {},
    fg = self.fg or conf.fg,
    bg = self.bg or conf.bg,
    pos = 1, co = {}, conf = {} }
  w.buf.win = w
  self.__index = self
  setmetatable(w, self)
  return w
end

function win:run(fn, ...)
  local c = { coroutine.create(fn), self, ... }
  table.insert(self.co, c)
  return c
end

function win:killproc()
  self.killed = true
  for _, v in ipairs(self.co) do
    if v.kill then
      v.kill()
    end
  end
  self.co = {}
end

function win:process()
  local status = self:autoscroll()
  local co = {}
  for _, v in ipairs(self.co) do
    if coroutine.status(v[1]) == 'suspended' then
      local r, e = coroutine.resume(table.unpack(v))
      if not r then
        return false, e
      end
      table.insert(co, v)
      status = true
    else
      print("Proc died")
    end
  end
  self.co = co
  if status then
    self:flush()
    self:show()
  end
  return status
end

function win:geom(x, y, w, h)
  self.x = x or self.x
  self.y = y or self.y
  self.w = w or self.w
  self.h = h or self.h
  self.marg = math.floor(scr.spw/2)
  h = h - self.marg*2
  w = w - self.marg*2 - scr.spw
  self.rows = math.floor(h / scr.sph)
  self.cols = math.floor(w / scr.spw)
  self:flush()
  self:scroller()
end

function win:flush()
  screen:clear(self.x, self.y, self.w, self.h, self.bg)
  for y = 0, self.rows do
    self.glyphs[y] = {}
    for x = 0, self.cols do
      self.glyphs[y][x] = {
        glyph = scr:glyph(" ", conf.fg),
        bg = self.bg,
        cursor = nil
      }
    end
  end
end

function win:pos2off(x, y)
  x, y = (x + 1)* scr.spw + self.marg,
    y * scr.sph + self.marg
  return x, y
end

function win:off2pos(x, y)
  x = math.floor((x - scr.spw + scr.spw/2 - self.marg) / scr.spw)
  y = math.floor((y - self.marg) / scr.sph)
  x = math.min(x, self.cols)
  y = math.min(y, self.rows)
  x = math.max(x, 0)
  y = math.max(y, 0)
  return x, y
end

function win:glyph(x, y, sym, fg, bg)
  fg = fg or self.fg
  bg = bg or self.bg
  local g = scr:glyph(sym, fg)
  local s = self.glyphs[y][x]
  if s.glyph == g and s.bg == bg and not s.cursor then
    return
  end
  s.glyph, s.bg, s.cursor = g, bg, false

  local first = x == 0

  x, y = self:pos2off(x, y)
  screen:offset(self.x, self.y)
  if first then
    screen:clear(x - self.marg, y, self.marg, scr.sph, self.bg)
  end
  screen:clear(x, y, scr.spw, scr.sph, bg)
  if g then
    g:blend(screen, x, y)
  end
  screen:nooffset()
end

function win:next(pos, x, y)
  local s = self.buf.text[pos]
  if s == '\n' then
    x = 0
    y = y + 1
  elseif s == '\t' then
    local ts = self:getconf 'ts'
    x = (math.floor(x / ts) + 1) * ts
  else
    x = x + 1
  end
  if x >= self.cols then
    x = 0
    y = y + 1
  end
  return x, y
end

function win:posln()
  local cur = self.buf.cur
  local opos = self.pos

  self.pos = self.buf:linestart(self.pos)
  self.buf.cur = cur

  local x, y, y0 = 0, 0
  local last = self.pos
  for i = self.pos, opos do
    y0 = y
    x, y = self:next(i, x, y)
    if y > y0 then
      self.pos = last
      last = i + 1
    end
  end
end

function win:toline(nr, sel)
  if nr == 0 then return end
  local found = self.buf:toline(nr)
  if not self:curvisible() or not found then
    self.pos = self.buf.cur
    if not found then
      self:posln()
    end
    self:prevpage(math.floor(self.rows / 2))
  end

  local start = self.buf.cur
  if sel ~= false then
    self.buf:lineend()
    self.buf:setsel(start, self.buf.cur)
  end
end

function win:nextpage(jump)
  local x, y = 0, 0
  jump = jump or self.rows
  for i = self.pos, #self.buf.text do
    if y >= jump then
      self.pos = i
      break
    end
    x, y = self:next(i, x, y)
  end
end

function win:prevpage(jump)
  jump = jump or self.rows
  local len = 0
  while self.pos > 1 do
    local last = self.pos
    self.pos = self.pos - 1
    self:posln()
    local x, y = 0, 0
    for k = self.pos, last do
      x, y = self:next(k, x, y)
    end
    len = len + y
    if self.buf.text[self.pos] == '\n' then
      len = len - 1
    end
    if len >= jump then
      self:posln()
      break
    end
  end
end

function win:nextline()
  local x, y
  x, y = 0, 0
  for i = self.pos, #self.buf.text do
    x, y = self:next(i, x, y)
    if y > 0 then
      self.pos = i + 1
      return true
     end
  end
  return false
end

function win:off2cur(x, y)
  x, y = self:off2pos(x, y)
  local nl
  local gl = self.glyphs[y]
  for i = x, 0, -1 do
    if gl[i].pos then
      return gl[i].pos, nl
    end
    nl = true
  end
  return math.max(#self.buf.text + 1, 1)
end

function win:realheight()
  local x, y = 0, 0
  for i = 1, #self.buf.text do
    x, y = self:next(i, x, y)
  end
  return (y + 1)*scr.sph + self.marg*2
end

function win:bottom()
  return self.y + self.h
end

function win:cur(pos)
  local o = self.buf.cur
  if pos then
    self.buf.cur = math.min(pos, #self.buf.text + 1)
    self.buf.cur = math.max(self.buf.cur, 1)
  end
  return o
end

function win:history(...)
  return self.buf:history(...)
end

function win:cursor(x, y)
  self.glyphs[y][x].cursor = true
  if x > 0 then
    self.glyphs[y][x-1].cursor = true
  end
  screen:offset(self.x, self.y)
  x, y = self:pos2off(x, y)
  local w = conf.text_cursor:size()
  conf.text_cursor:blend(screen, math.floor(x-w/2), y)
  screen:nooffset()
end

function win:scroller()
  if not self.pos or not self.epos or self.h == 0 then
    return
  end

  local len = #self.buf.text
  local top = math.floor((self.pos / (len + 1)) * (self.h - 5))
  local bottom = math.floor(((self.epos or self.pos) / (len + 1)) * (self.h - 5))  if bottom - top <= scr.spw then
    bottom = top + scr.spw
  end
  screen:offset(self.x, self.y)
  screen:clear(0, 0, scr.spw, self.h, conf.bg)
  screen:rect(0, 0, scr.spw - 1, self.h - 1, conf.fg)

  if self.pos ~= 1 or len > self.epos + 1 then
    screen:fill_rect(2, 2 + top, 2 + scr.spw - 5, 2 + bottom, conf.fg)
  end
  screen:nooffset()
end

function win:flushline(x0, y0)
  for x = x0, self.cols - 1 do
    self:glyph(x, y0, false)
    self.glyphs[y0][x].pos = nil
  end
end

function win:show()
  if self.w <= 0 or self.h <= 0 or
    self.cols <= 0 or self.rows <= 0 then
    return
  end

  local x, y = 0, 0
  local x0, y0 = x, y
  local text = self.buf.text

  self.epos = #text + 1

  for i = self.pos, #text + 1 do
    self:glyph(x, y, text[i] or false,
      conf.fg,
      self.buf:insel(i) and conf.hl or self.bg)

    self.glyphs[y][x].pos = i

    if i == self.buf.cur then
      self.cx, self.cy = x, y
      if not self.buf:issel() then
        self:cursor(x, y)
      end
      self.autox = self.autox or x
    end

    x0, y0 = x, y
    x, y = self:next(i, x0, y0)

    if x > x0 and y == y0 and x - x0 > 1 then
      self:flushline(x0 + 1, y0)
    end
    if y > y0 then
      self:flushline(x0 + 1, y0)
    end
    if y >= self.rows then
      self.epos = i
      break
    end
  end

  if y == y0 then
    self:flushline(x0 + 1, y0)
    y = y + 1
  end
  while y < self.rows do
    self:flushline(0, y)
    y = y + 1
  end
  self:scroller()
end

function win:motion(x, y)
  local _, _, mb = input.mouse()
  if self.scrolling then
    self:scroll(y)
    return
  end
  if not self.autoscroll_on then
    return
  end
  local sel = self.buf:getsel()
  if not sel then return end
  if not mb.left then return end
  local e = self:off2cur(x, y)
  sel.e = e
  self.buf.cur = e
  return true
end

function win:autoscroll()
  if not self.autoscroll_on then return end
  local _, y, mb = input.mouse()
  if not mb.left or not self.buf:issel() then return end
  y = y - self.y
  if y < self.h - self.marg and y > self.marg then
    return
  end
  if self.scrolltime and sys.time() - self.scrolltime < conf.process_hz then
    return true
  end
  self.scrolltime = sys.time()
  if y >= self.h - self.marg then
    if not self:nextline() then
      return true
    end
    self.buf:getsel().e = self.epos
  elseif y < self.marg then
    if not self:prevline() then
      return true
    end
    self.buf:getsel().e = self.pos
  end
  self.buf.cur = self.buf:getsel().e
  return true
end

function win:get_active_text(exec, nl)
  local buf = self.buf
  local txt = buf:getseltext()
  local reset, s, e
  if not buf:issel() or (not buf:insel() and not nl) then
    reset = true
    s, e = buf:getsel().s, buf:getsel().e
    buf:selpar(exec and delim_exec)
    txt = buf:getseltext()
    buf.cur = buf:getsel().e
  end
  if not exec then
    if input.keydown 'alt' then
      buf.cur = buf:getsel().s
    else
      buf.cur = buf:getsel().e
    end
  elseif reset then
    buf:setsel(s, e)
  end
  return txt
end

function win:search(txt, back)
  if txt:startswith ':' and tonumber(txt:sub(2)) then
    self:toline(tonumber(txt:sub(2)))
    return
  end
  if self.buf:search(txt, back) then
    self:visible()
  end
end

function win:exec(txt)
  print("EXEC", txt)
end

function win:compl()
  local txt = self.buf:getseltext()
  if not self.buf:issel() then
    self.buf:selpar(delim_exec)
    txt = self.buf:getseltext()
  end
  if txt == self.last_compl then
    txt = self.last_compl_path
  else
    self.last_compl = false
    txt = txt:gsub("/+", "/")
  end
  if txt == '' then return end
  local d = sys.dirname(txt)
  self.last_compl_path = txt
  for _, f in ipairs(sys.readdir(d) or {}) do
    local path = (d ..'/'.. f):gsub("/+", "/"):esc()
    if self.last_compl then
      if self.last_compl == path then
        self.last_compl = false
      end
    elseif (path:startswith(txt) or path:startswith("./"..txt)) then
      self:input(path)
      self.last_compl = path
      break
    end
  end
end

function win:mouseup(mb, x, y)
  local _, _, st = input.mouse()

  self.autoscroll_on = false
  self.scrolling = false

  if (x < 0 or y < 0 or x >= self.w or y >= self.h) or st.left then
    return false
  end

  local nl
  local exec = mb == 'middle' or (mb == 'right' and input.keydown 'shift')
  if mb == 'right' or exec then
    self.buf.cur, nl = self:off2cur(x, y)
    local txt = self:get_active_text(exec, nl)
    if exec then
      self:exec(txt)
    else
      self:search(txt, input.keydown 'alt')
    end
  end
  return
end

function win:mousedown(mb, x, y)
  if x < 0 or x > self.w or y < 0 or y > self.h then
    return
  end
  local nl
  local _, _, st = input.mouse()
  if st.left and (st.right or st.middle) then
    if mb == 'middle' then
      self:cut()
    elseif mb == 'right' then
      self:paste()
    end
    return
  end
  if mb ~= 'left' then
    self.buf.cur = self:off2cur(x, y)
    return
  end
  if x < scr.spw then
    self:scroll(y)
    self.scrolling = true
  else
    self.buf.cur, nl = self:off2cur(x, y)
    self.autox = self:off2pos(x, y)
    local sel = self.buf:getsel()
    if sel.s == self.buf.cur and sel.e == sel.s then
      if nl then
        self.buf:sel_line(true)
      else
        self:selpar()
      end
      self.autoscroll_on = false
    else
      self.buf:setsel(self.buf.cur, self.buf.cur)
      self.autoscroll_on = true
    end
  end
end

function win:tox(tox)
  if not tox then return end
  local x, y, y0 = 0, 0
  local pos = self.buf.cur
  for i = pos, #self.buf.text do
    y0 = y
    self.buf.cur = i
    x, y = self:next(i, x, y)
    if y > y0 or x > tox then
      break
    end
  end
end

function win:prevline()
  if self.pos <= 1 then return end
  self.pos = self.glyphs[0][0].pos - 1
  self:posln()
  self.glyphs[0][0].pos = self.pos
  return true
end

function win:movesel()
  if input.keydown 'shift' then
    self.buf:getsel().e = self.buf.cur
    return true
  else
    self.buf:resetsel()
  end
end

function win:up()
  if self:visible() then
    return
  end
  local x, y = self.cx, self.cy
  if y == 0 then -- scroll to prev line
    if self.pos <= 1 then return end
    self:prevline()
    self.buf.cur = self.pos
    self:tox(self.autox or x)
  else
    for i = self.autox or x, 0, -1 do
      local gl = self.glyphs[y - 1][i]
      if gl.pos then
        self.buf.cur = gl.pos
        break
      end
    end
  end
end

function win:down()
  if self:visible() then
    return
  end
  local x, y = self.cx, self.cy
  local last = self.buf.cur
  for i = self.buf.cur, #self.buf.text+1 do
    if y > self.cy + 1 then
      break
    end
    if y == self.cy + 1 and
      x > (self.autox or self.cx) then
      break
    end
    last = i
    x, y = self:next(i, x, y)
  end
  if y >= self.rows then
    self:nextline()
  end
  self.buf.cur = last
end

function win:scroll(off)
  if off <= 0 then return end
  self.pos = math.floor((off / self.h) * #self.buf.text) + 1
  self:posln()
--  self:flush()
end

function win:set(text)
  self.buf:set(text)
end

function win:resetsel(text)
  self.buf:resetsel(text)
end

function win:append(text, cur)
  self.buf:append(text, cur)
  if cur then
    self:visible()
  end
end

function win:tail()
  self.buf:tail()
  self:visible()
end

function win:printf(fmt, ...)
  self:append(string.format(fmt, ...))
end

function win:clear()
  self.buf:set ""
  self.buf.cur = 1
  self.pos = 1
end

function win:load(fname)
  return self.buf:load(fname)
end

function win:file(fname)
  return self.buf:loadornew(fname)
end

function win:curvisible()
  return self.epos and self.buf.cur >= self.pos and
    self.buf.cur <= self.epos
end

function win:visible()
  if not self:curvisible() then
    self.pos = self.buf.cur
    self:posln()
    self:prevpage(math.floor(self.rows / 2))
    return true
  end
end

function win:left()
  self:visible()
  self.buf:left()
  self.autox = false
end

function win:right()
  self:visible()
  self.buf:right()
  self.autox = false
end

function win:input(t)
  self:visible()
  self.input_start = self.input_start or self.buf.cur
  self.buf:input(t)
  self.autox = false
end

function win:getconf(name)
  if self.conf[name] ~= nil then
    return self.conf[name]
  end
  return conf[name]
end

function win:delete()
end

function win:backspace()
  if self:visible() then
    return
  end
  if self:getconf 'spaces_tab' then
    local len = self.cx % self:getconf 'ts'
    len = len == 0 and self:getconf 'ts' or len
    for i = 1, len do
      if self.buf.text[self.buf.cur-i] ~= ' ' then
        len = 1
        break
      end
    end
    len = math.max(len, 1)
    self.buf:history 'start'
    for _ = 1, len do
      self.buf:backspace()
    end
    self.buf:history 'end'
  else
    self.buf:backspace()
  end
  self:visible()
  self.autox = false
  self.input_start = false
end

function win:escape()
  self:visible()
  if self.buf:issel() then
    self.buf:cut()
  elseif self.input_start then
    self.buf:setsel(self.input_start, self.buf.cur)
  end
  self.autox = false
  self.input_start = false
end

function win:newline()
  self:visible()
  self.buf:newline()
  self.autox = false
end

function win:lineend()
  self:visible()
  self.buf:lineend()
  self.autox = false
end

function win:linestart()
  self:visible()
  self.buf:linestart()
  self.autox = false
end

function win:undo()
  self:visible()
  self.buf:undo()
  self.autox = false
  self.input_start = false
end

function win:paste()
  self:visible()
  self.buf:paste()
  self.autox = false
  self.input_start = false
end

function win:cut(copy)
--  self:visible()
  self.buf:cut(copy)
  self:visible()
  self.autox = false
  self.input_start = false
end

function win:kill()
  self:visible()
  self.buf:kill()
  self.autox = false
  self.input_start = false
end

function win:selpar()
  self:visible()
  self.buf:selpar()
  self.autox = false
end

function win:changed(fl)
  return self.buf:changed(fl)
end

function win:dirty(dirty)
  if dirty ~= nil then
    self.isdirty = dirty
  end
  return self.buf and self.buf:isfile() and self.isdirty
end

function win:nodirty()
  self.isdirty = false
  self.buf:dirty(false)
end

function win:event(r, v, a, b)
  if not r then return end
  local mx, my = input.mouse()
  if (r ~= 'mousemotion' and r ~= 'mouseup') and
    (mx < self.x or my < self.y or
    mx >= self.x + self.w or
    my >= self.y + self.h) then
      return false
  end
  if r == 'mousedown'  then
    self:mousedown(v, a - self.x, b - self.y)
  elseif r == 'mouseup' then
    return self:mouseup(v, a - self.x, b - self.y)
  elseif r == 'mousemotion' then
    return self:motion(v - self.x, a - self.y)
  elseif r == 'mousewheel' then
    if v > 0 then
      for _ = 1, math.abs(v) do
        self:prevline()
      end
    else
      for _ = 1, math.abs(v) do
        self:nextline()
      end
    end
  elseif r == 'text' then
    self:input(v)
  elseif r == 'keydown' then
    if v == 'left' then
      self:left()
      self:movesel()
    elseif v == 'right' then
      self:right()
      self:movesel()
    elseif v == 'up' then
      self:up()
      self:movesel()
    elseif v == 'down' then
      self:down()
      self:movesel()
    elseif v == 'pageup' or v == 'keypad 9' then
      self:prevpage()
      self.buf.cur = self.pos
      self:tox(self.autox)
      self:movesel()
    elseif v == 'pagedown' or v == 'keypad 3' then
      self:nextpage()
      self.buf.cur = self.pos
      self:tox(self.autox)
      self:movesel()
    elseif v == 'return' then
      self:newline()
    elseif v == 'backspace' then
      self:backspace()
    elseif v == 'delete' then
      self:delete()
    elseif v == 'escape' then
      self:escape()
    elseif v:find 'shift' then
      if not self.buf:issel() then
        self.buf:setsel(self.buf.cur, self.buf.cur)
      end
    elseif (v == 'e' and input.keydown 'ctrl') or v == 'end' then
      self:lineend()
    elseif (v == 'a' and input.keydown 'ctrl') or v == 'home' then
      self:linestart()
    elseif v == 'z' and input.keydown 'ctrl' then
      self:undo()
    elseif v == 'w' and input.keydown 'ctrl' then
      self:selpar()
    elseif v == 'v' and input.keydown 'ctrl' then
      self:paste()
    elseif v == 'c' and input.keydown 'ctrl' then
      self:cut(true)
    elseif v == 'x' and input.keydown 'ctrl' then
      self:cut()
    elseif v == 'f' and input.keydown 'ctrl' then
      self:compl()
    elseif v == 'k' and input.keydown 'ctrl' then
      self:kill()
    elseif v == 's' and input.keydown 'ctrl' then
      if self.buf:isfile() then
        self:save()
        self.frame:update()
      end
    elseif v == 'tab' then
      if self:visible() then
        return
      end
      local sp_tab = self:getconf 'spaces_tab'
      if not sp_tab then
        self:input '\t'
      else
        local ts = self:getconf'ts'
        local l = ts - (self.cx % ts)
        local t = ''
        for _ = 1, l do
          t = t .. ' '
        end
        self:input(t)
      end
    end
  end
  return true
end

return win
