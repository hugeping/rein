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

local function say(out, text, gen)
  -- the page may be stale already: the window went elsewhere while
  -- this one was being read
  if gen and out.gem.gen ~= gen then
    return false
  end
  out:printf("%s", text)
  out:scroll_output()
  return true
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

-- a 60 response: offer to make a certificate for the host
function gemini.cert_prompt(w, url, host)
  w:printf('? %s requires a client certificate, create one? [Enter] ',
    host)
  w.gem.cert = { url = url, host = host, pos = #w.buf.text + 1 }
  w:cur(#w.buf.text + 1)
end

-- a client certificate lives in $HOME/.rein/gemini/certs (or under
-- DATADIR/save), one pair per host: a certificate is an identity, so
-- it is made only with the user's consent
local function cert_file(host, ext)
  local ok, dir = pcall(sys.appdir, 'gemini')

  if not ok or not dir then
    return
  end
  dir = dir .. '/certs'
  sys.mkdir(dir)
  return dir .. '/' .. (host:lower():gsub('[^%w%._%-]', '_')) .. ext
end

local function cert_load(host)
  local crt, key = cert_file(host, '.crt'), cert_file(host, '.key')

  if crt and key and io.access(crt) and io.access(key) then
    return io.file(crt), io.file(key)
  end
end

local function cert_make(host)
  local crt, key = cert_file(host, '.crt'), cert_file(host, '.key')

  if not crt then
    return false, "no certificate directory"
  end
  local c, k = net.certgen(host)

  if not c then
    return false, k
  end
  local ok, e = io.file(crt, c)

  if not ok then
    return false, e
  end
  ok, e = io.file(key, k)
  if not ok then
    return false, e
  end
  return c, k
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

local function fetch(out, url, depth, gen)
  local g = out.gem
  local u = parse(url)

  if not u then
    say(out, "bad url: " .. url .. "\n", gen)
    return false
  end
  if depth == 0 then
    out:clear()
    out.gem.links = {}
  end
  out.gem.url = url
  if not say(out, string.format("%s%s\n", url,
    depth > 0 and " (redirect)" or ""), gen) then
    return false
  end

  local cert, key = cert_load(u.host)
  local s, e = sock.dial(u.host, u.port, u.host, cert, key)
  if not s then
    say(out, "error: " .. tostring(e) .. "\n", gen)
    return false
  end
  g.sock = s
  if g.gen ~= gen then
    g.sock = nil
    s:close()
    return false
  end
  if not s:write(url .. "\r\n") then
    say(out, "error: send failed\n", gen)
    s:close()
    g.sock = nil
    return false
  end

  local line, le = s:readln(true)
  if g.gen ~= gen then
    s:close()
    g.sock = nil
    return false
  end
  if not line then
    say(out, "error: " .. tostring(le or "closed") .. "\n", gen)
    s:close()
    g.sock = nil
    return false
  end
  local status = tonumber(line:sub(1, 2))
  local meta = line:sub(4)
  if not status then
    say(out, "error: bad response\n", gen)
    s:close()
    g.sock = nil
    return false
  end
  say(out, string.format("[%d %s]\n", status, meta), gen)

  if status == 60 then
    -- the server wants a client certificate: make one, but only
    -- after the user agrees; a certificate already sent is not
    -- replaced by a new one, the server just did not take it
    s:close()
    g.sock = nil
    if cert then
      say(out, "the certificate is already in use\n", gen)
    else
      gemini.cert_prompt(out, url, u.host)
    end
    return g.gen == gen
  end
  if status == 61 then
    say(out, "the server does not authorise this certificate\n", gen)
  elseif status == 62 then
    say(out, "the certificate is not valid\n", gen)
  end

  if status >= 10 and status < 20 then
    gemini.prompt(out, url, meta)
    s:close()
    g.sock = nil
    return true
  end

  if status >= 20 and status < 30 then
    local n = 0

    -- not "for l in s:lines()": on EOF the iterator yields false,
    -- which would never end the loop
    while true do
      local l = s:readln(true)

      if not l or g.gen ~= gen then
        break
      end
      out:printf("%s\n", l)
      n = n + 1
      if n % 32 == 0 then
        out:scroll_output()
        coroutine.yield(true)
      end
    end
    s:close()
    g.sock = nil
    if g.gen ~= gen then
      return false
    end
    out:scroll_output()
    gemini.scan(out)
    return true
  end

  s:close()
  g.sock = nil
  if status >= 30 and status < 40 and depth < 5
    and meta:find("^gemini://")
  then
    return fetch(out, meta, depth + 1, gen)
  end
  return g.gen == gen
end

-- show hist[pos] in the window; a redirect updates the entry to the
-- page actually loaded.  A new navigation cancels the previous one:
-- its socket is closed and the generation stops it from writing
local function go(w, pos)
  local g = w.gem

  g.input = nil -- a pending 10/11 prompt is stale after a navigation
  g.cert = nil -- so is a pending 60 offer
  g.gen = (g.gen or 0) + 1
  if g.sock then
    g.sock:close()
    g.sock = nil
  end
  g.pos = pos
  w.cmdline = gemini.words(w)
  w.frame:update()
  local gen = g.gen

  w:run(function()
    local url = g.hist[pos]

    if fetch(w, url, 0, gen) and g.pos == pos and g.gen == gen then
      g.hist[pos] = w.gem.url
    end
  end)
end

-- the user agreed to a certificate: make it and retry the page
local function cert_retry(w)
  local c = w.gem.cert

  if not c then
    return
  end
  w.gem.cert = nil
  local crt, err = cert_make(c.host)

  if not crt then
    w:printf("error: %s\n", err or "no certificate")
    w:scroll_output()
    return
  end
  go(w, w.gem.pos)
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
  local g = out.gem

  -- as in go(): this navigation cancels the one in flight
  g.gen = (g.gen or 0) + 1
  if g.sock then
    g.sock:close()
    g.sock = nil
  end
  return fetch(out, url, 0, g.gen)
end

-- set a window up as a page window: link clicks, history and dump
function gemini.win(w)
  w.gem = w.gem or { links = {}, hist = {}, pos = 0 }
  -- gemtext: highlight the page and wrap its words, as markdown does;
  -- the kind keeps these when a rename re-reads the file presets
  w.kind_conf = { syntax = "gemini", wrap = true }
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

-- alt click: the page gets a window of its own ("+gemini2", "+gemini3",
-- ...), so a link can be read next to the one it came from
local function new_page(w, url)
  local root = w.frame:main()
  local n = 2

  while root:win_by_name("+gemini" .. n) do
    n = n + 1
  end
  local out = w.frame:open_err("+gemini" .. n)

  out.cwd = nil
  gemini.win(out)
  gemini.follow(out, url)
  return out
end

function gemini:event(r, v, a, b)
  -- win:mouseup execs the text under the cursor with the middle button,
  -- so a link click must be caught (and consumed) there; http(s) links
  -- are not gemini's business and are left to it (uri.lua opens them)
  if r == 'mouseup' and v == 'middle' then
    local url = gemini.link_at(self, a - self.x, b - self.y)

    if url and not url:find("^https?://") then
      if input.keydown 'alt' then
        new_page(self, url)
      else
        gemini.follow(self, url)
      end
      return true
    end
  end
  return win.event(self, r, v, a, b)
end

-- return in the body sends the typed answer of a pending input or
-- accepts the offer of a client certificate
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
  local c = self.gem.cert

  if c and self.buf.cur >= c.pos then
    cert_retry(self)
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
