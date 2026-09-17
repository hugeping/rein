-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
--
-- Minimal Gemini client (gemini://, TLS on port 1965) for red.  A page
-- lives in a "+gemini" output window: the window keeps the current url
-- and the "=>" links of the page, so a middle click can follow a link
-- and win.kinds.gemini can restore it from red.dump.  Requests run in
-- a window coroutine (win:run), so the editor stays alive while the
-- request is in flight.
local sock = require "sock"
local win = require "red/win"

local gemini = {}

local function say(out, text)
  out:printf("%s", text)
  out:scroll_output()
end

-- gemini://host[:port][/path] (the port defaults to 1965)
local function parse(url)
  local host, port, path = url:match("^gemini://([^:/]+):?(%d*)/?(.*)$")

  if not host then
    return nil
  end
  return {
    host = host,
    port = tonumber(port) or 1965,
    path = path or '',
  }
end

-- a link as written in the page, made absolute against the page url
function gemini.resolve(base, url)
  if url:find("^%a+://") then
    return url
  end
  local host, port, path
  if base then
    host, port, path = base:match("^gemini://([^:/]+):?(%d*)/?(.*)$")
  end
  if not host then
    return url
  end
  local prefix = "gemini://" .. host ..
    (port ~= '' and ':' .. port or '')
  if url:find("^/") then
    return prefix .. url
  end
  local dir = (path or ''):match("^(.*)/")
  return prefix .. '/' .. (dir and dir .. '/' or '') .. url
end

-- collect the "=>" links of the page; pos and e are buffer offsets
function gemini.scan(w)
  local links = {}
  local text = w.buf.text
  local start = 1
  for i = 1, #text + 1 do
    if i > #text or text[i] == '\n' then
      local line = w.buf:gettext(start, i - 1)
      local url = line:match("^%s*=>%s*(%S+)")
      if url then
        table.insert(links, {
          pos = start,
          e = i - 1,
          url = gemini.resolve(w.gem.url, url),
        })
      end
      start = i + 1
    end
  end
  w.gem.links = links
  return links
end

-- the url of the link at the buffer position, nil if there is none
function gemini.link_pos(w, pos)
  for _, l in ipairs(w.gem.links) do
    if pos >= l.pos and pos <= l.e then
      return l.url
    end
  end
end

-- the link under the window-local point
function gemini.link_at(w, x, y)
  if x < 0 or y < 0 or x > w.w or y > w.h then
    return
  end
  return gemini.link_pos(w, w:off2cur(x, y))
end

-- the url with the user input as its query component (spaces are
-- %20, an existing query is replaced as the spec requires)
function gemini.query(url, text)
  local base = url:match('^([^?]*)') or url
  local q = text:gsub('[^%w%-%._~]', function(c)
    return string.format('%%%02X', c:byte())
  end)
  return base .. '?' .. q
end

-- a 1x response: ask for input right in the window
function gemini.prompt(w, url, meta)
  w:printf('? %s ', meta)
  w.gem.input = { url = url, pos = #w.buf.text + 1 }
  w:cur(#w.buf.text + 1)
end

-- send the typed answer to the pending input request
function gemini.answer(w, text)
  local i = w.gem.input

  if not i then
    return
  end
  w.gem.input = nil
  return gemini.follow(w, gemini.query(i.url, text))
end

local function fetch(out, url, depth)
  local u = parse(url)

  if not u then
    say(out, "bad url: " .. url .. "\n")
    return false
  end
  if depth == 0 then
    out:clear()
    out.gem.links = {}
  end
  out.gem.url = url
  say(out, string.format("%s%s\n", url,
    depth > 0 and " (redirect)" or ""))

  local s, e = sock.dial(u.host, u.port, u.host)
  if not s then
    say(out, "error: " .. tostring(e) .. "\n")
    return false
  end
  if not s:write(url .. "\r\n") then
    say(out, "error: send failed\n")
    s:close()
    return false
  end

  local line, le = s:readln(true)
  if not line then
    say(out, "error: " .. tostring(le or "closed") .. "\n")
    s:close()
    return false
  end
  local status = tonumber(line:sub(1, 2))
  local meta = line:sub(4)
  if not status then
    say(out, "error: bad response\n")
    s:close()
    return false
  end
  say(out, string.format("[%d %s]\n", status, meta))

  if status >= 10 and status < 20 then
    gemini.prompt(out, url, meta)
    return true
  end

  if status >= 20 and status < 30 then
    local n = 0

    -- not "for l in s:lines()": on EOF the iterator yields false,
    -- which would never end the loop
    while true do
      local l = s:readln(true)

      if not l then
        break
      end
      out:printf("%s\n", l)
      n = n + 1
      if n % 32 == 0 then
        out:scroll_output()
        coroutine.yield(true)
      end
    end
    out:scroll_output()
    s:close()
    gemini.scan(out)
    return true
  end

  s:close()
  if status >= 30 and status < 40 and depth < 5
    and meta:find("^gemini://")
  then
    return fetch(out, meta, depth + 1)
  end
  return true
end

-- show hist[pos] in the window; a redirect updates the entry to the
-- page actually loaded
local function go(w, pos)
  local g = w.gem

  g.input = nil -- a pending 10/11 prompt is stale after a navigation
  g.pos = pos
  w.cmdline = gemini.words(w)
  w.frame:update()
  w:run(function()
    local url = g.hist[pos]

    if fetch(w, url, 0) and g.pos == pos then
      g.hist[pos] = w.gem.url
    end
  end)
end

-- navigate to a link or to "host", "host/path", "gemini://...",
-- remembering the page in the history
function gemini.follow(w, url)
  gemini.win(w)
  if not url:find("^gemini://") then
    url = "gemini://" .. url
  end
  local g = w.gem

  for i = #g.hist, g.pos + 1, -1 do
    table.remove(g.hist, i)
  end
  g.hist[g.pos + 1] = url
  return go(w, g.pos + 1)
end

function gemini.back(w)
  if w.gem.pos > 1 then
    go(w, w.gem.pos - 1)
  end
  return true
end

function gemini.forward(w)
  if w.gem.pos < #w.gem.hist then
    go(w, w.gem.pos + 1)
  end
  return true
end

-- the command line of the window: an action is shown only when it is
-- available now (the frame renders it as a clickable command word)
function gemini.words(w)
  local g = w.gem
  local t = ''
  if g.pos > 1 then
    t = t .. 'Back '
  end
  if g.pos < #g.hist then
    t = t .. 'Forward '
  end
  return t .. (w.scroll_mode and 'Noscroll' or 'Scroll')
end

-- target is "host", "host/path" or a full "gemini://..." url
function gemini.fetch(out, target)
  gemini.win(out)
  local url = target:find("^gemini://") and target
    or ("gemini://" .. target)

  return fetch(out, url, 0)
end

-- set a window up as a page window: link clicks, history and dump
function gemini.win(w)
  w.gem = w.gem or { links = {}, hist = {}, pos = 0 }
  w.cmd = setmetatable(
    { Back = gemini.back, Forward = gemini.forward },
    { __index = win.cmd })
  w.cmdline = gemini.words(w)
  w.dump = gemini.dump
  w.event = gemini.event
  w.keydown_event = gemini.keydown_event
  w.newline = gemini.newline
  w.Get = gemini.Get
  return w
end

-- the menu "Get" re-reads the page instead of the file
function gemini:Get()
  local g = self.gem

  if g.pos > 0 then
    go(self, g.pos)
  elseif g.url then
    gemini.follow(self, g.url)
  end
  return true
end

function gemini:event(r, v, a, b)
  -- win:mouseup execs the text under the cursor with the middle button,
  -- so a link click must be caught (and consumed) there; http(s) links
  -- are not gemini's business and are left to it (uri.lua opens them)
  if r == 'mouseup' and v == 'middle' then
    local url = gemini.link_at(self, a - self.x, b - self.y)

    if url and not url:find("^https?://") then
      gemini.follow(self, url)
      return true
    end
  end
  return win.event(self, r, v, a, b)
end

-- return in the body sends the typed answer of a pending input
function gemini:newline()
  local i = self.gem.input

  if i and self.buf.cur >= i.pos then
    local t = ''
    for k = i.pos, #self.buf.text do
      if self.buf.text[k] == '\n' then
        break
      end
      t = t .. self.buf.text[k]
    end
    gemini.answer(self, t)
    return
  end
  return win.newline(self)
end

function gemini:keydown_event(v)
  if input.keydown 'alt' then
    if v == 'left' then
      return gemini.back(self)
    elseif v == 'right' then
      return gemini.forward(self)
    end
  end
  return win.keydown_event(self, v)
end

function gemini:dump()
  local d = win.dump(self)
  d.type = 'gemini'
  d.url = self.gem.url
  d.hist = self.gem.hist
  d.pos = self.gem.pos
  d.input = self.gem.input
  return d
end

win.kinds.gemini = function(fr, d, idx)
  local w = win.kinds.win(fr, d, idx)
  if not w then return end
  w.gem = { links = {}, hist = d.hist or {}, pos = d.pos or 0,
    input = d.input }
  gemini.win(w)
  w.gem.url = d.url
  gemini.scan(w)
  return w
end

local function fetch_page(w, target)
  if not target then return end
  w = w:output "+gemini"
  w.cwd = nil
  gemini.follow(w, target)
  return true
end

return {
  gemini = fetch_page,
}
