local win = require "red/win"
local sock = require "sock"

-- the fake TLS exchange: sock.dial returns canned response lines and
-- the requests are recorded; the extension requires the same sock table
local real_dial = sock.dial
local responses, requests, dials
local function fake_dial(host, port, tls, cert, key)
  table.insert(dials, { host, port, tls, cert, key })
  local lines = table.remove(responses, 1) or { "20 text/gemini" }
  local i = 0
  return {
    write = function(_, t)
      table.insert(requests, t)
      return true
    end,
    readln = function()
      i = i + 1
      return lines[i]
    end,
    -- the rest of the lines as raw bytes, for Save
    recv = function()
      if i >= #lines then
        return nil
      end
      local rest = table.concat(lines, "\r\n", i + 1) .. "\r\n"
      i = #lines
      return rest
    end,
    close = function() end,
  }
end
sock.dial = fake_dial

local ext = require "red/proc/gemini"

local certdir = "/tmp/rein-gemini/certs"
local h_crt, h_key = certdir .. "/h.crt", certdir .. "/h.key"

local function fake_frame()
  local fr = { update = function() end }
  fr.file = function(_, fname)
    local w = win:new(fname)
    w.frame = fr
    return w
  end
  return fr
end

-- a page window built the way red.dump restores one
local function page(text, url, extra)
  local d = { type = "gemini", fname = "+gemini", text = text, url = url }
  for k, v in pairs(extra or {}) do
    d[k] = v
  end
  return win.kinds.gemini(fake_frame(), d, 1)
end

local function pump(w)
  while #w.co > 0 do
    local co = w.co
    w.co = {}
    for _, v in ipairs(co) do
      if coroutine.status(v[1]) == 'suspended' then
        local ok, e = coroutine.resume(table.unpack(v))
        if not ok then error(e) end
        table.insert(w.co, v)
      end
    end
  end
end

local function new_page()
  local w = win:new("+gemini")
  w.frame = { update = function() end }
  return w
end

-- run the "gemini <target>" proc and wait for the page
local function run(target)
  local w = new_page()
  ok(ext.gemini({ output = function() return w end }, target))
  pump(w)
  return w
end

local function reset()
  requests, dials = {}, {}
end

-- the certificate directory is faked and tls.certgen is stubbed; the
-- hosts it was called for are collected in `made`
local made
local function with_certs(files, fn)
  local old_file, old_access = io.file, io.access
  local old_appdir, old_mkdir = sys.appdir, sys.mkdir
  local old_tls = tls

  made = {}
  io.file = function(f, d)
    if d == nil then
      return files[f]
    end
    files[f] = d
    return true
  end
  io.access = function(f) return files[f] ~= nil end
  sys.appdir = function(app) return "/tmp/rein-" .. app end
  sys.mkdir = function() return true end
  tls = {
    certgen = function(host)
      table.insert(made, host)
      return "CRT " .. host, "KEY " .. host
    end,
  }
  local ok, e = pcall(fn)
  io.file, io.access = old_file, old_access
  sys.appdir, sys.mkdir = old_appdir, old_mkdir
  tls = old_tls
  if not ok then error(e) end
end

local function with_alt(fn)
  local old = input.keydown
  input.keydown = function(m) return m == 'alt' end
  local ok, e = pcall(fn)
  input.keydown = old
  if not ok then error(e) end
end

local function with_shift(fn)
  local old = input.keydown
  input.keydown = function(m) return m == 'shift' end
  local ok, e = pcall(fn)
  input.keydown = old
  if not ok then error(e) end
end

-- the files written by Save are collected in a table
local function with_save(fn)
  local files = {}
  local old = io.file
  io.file = function(f, d)
    if d == nil then
      return files[f]
    end
    files[f] = d
    return true
  end
  local ok, e = pcall(fn, files)
  io.file = old
  if not ok then error(e) end
end

describe("gemini", function()
  it("fetches a page, sends the request and collects the links", function()
    reset()
    responses = { { "20 text/gemini", "=> gemini://h/a one", "=> /b",
      "=> rel", "plain" } }
    local w = run("h/dir/page")
    eq(requests[1], "gemini://h/dir/page\r\n")
    eq(dials[1][1], "h")
    eq(dials[1][2], 1965)
    eq(dials[1][3], "h")
    eq(w.gem.url, "gemini://h/dir/page")
    eq(#w.gem.links, 3)
    eq(w.gem.links[1].url, "gemini://h/a")
    eq(w.gem.links[2].url, "gemini://h/b")
    eq(w.gem.links[3].url, "gemini://h/dir/rel")
    ok(w:gettext():find("plain", 1, true))
  end)

  it("the link offsets count symbols, not bytes", function()
    responses = { { "20 text/gemini", "привет", "=> gemini://h/a" } }
    local w = run("h/x")
    -- url line + status line + "привет", all in symbols
    eq(w.gem.links[1].pos, 38)
    eq(w.gem.links[1].e, 38 + ("=> gemini://h/a"):len() - 1)
  end)

  it("no target: nothing happens", function()
    eq(ext.gemini({}), nil)
  end)

  it("a middle click on a link follows it, off a link it execs", function()
    local w = page("=> gemini://h/a one\n=> gemini://h/b two\n")
    w.x, w.y, w.w, w.h = 0, 0, 100, 100
    local asked, executed = {}, {}
    w.run = function(_, f)
      table.insert(asked, f)
      return {}
    end
    w.exec = function(_, t) table.insert(executed, t) end
    w.off2cur = function() return 3 end
    ok(w:event('mouseup', 'middle', 20, 5))
    eq(#asked, 1)
    eq(w.gem.hist[#w.gem.hist], "gemini://h/a")
    eq(#executed, 0, "the link click is not executed as a command")
    w.off2cur = function() return 21 end -- the second link line
    ok(w:event('mouseup', 'middle', 20, 5))
    eq(w.gem.hist[#w.gem.hist], "gemini://h/b")
    eq(#executed, 0)
    w.off2cur = function() return 40 end -- end of the page, no link there
    w:event('mouseup', 'middle', 20, 5)
    eq(#asked, 2, "a click outside the links does not navigate")
    eq(#executed, 1, "win:mouseup executes it as a command")
  end)

  it("follows a redirect and remembers the final url", function()
    reset()
    responses = { { "31 gemini://h/new" }, { "20 text/gemini", "ok" } }
    local w = run("h/old")
    eq(requests[1], "gemini://h/old\r\n")
    eq(requests[2], "gemini://h/new\r\n")
    eq(w.gem.url, "gemini://h/new")
    eq(w.gem.hist[w.gem.pos], "gemini://h/new")
    ok(w:gettext():find("(redirect)", 1, true))
  end)

  it("resolves relative links per RFC 3986", function()
    reset()
    responses = { { "20 text/gemini",
      "=> ?39 query only",
      "=> x same directory",
      "=> ./x same directory",
      "=> ../x one up",
      "=> /x from the root",
      "=> //h2/x another authority",
      "=> gemini://h2/y?q#f absolute, fragment dropped",
      "=> #f same page, fragment dropped",
      "=> a//b an empty segment stays",
      "=> .. one up, trailing slash",
    } }
    local w = run("h/settings/avatar/V5XoC8e7xT")
    local u = {}

    for i, l in ipairs(w.gem.links) do
      u[i] = l.url
    end
    eq(u[1], "gemini://h/settings/avatar/V5XoC8e7xT?39")
    eq(u[2], "gemini://h/settings/avatar/x")
    eq(u[3], "gemini://h/settings/avatar/x")
    eq(u[4], "gemini://h/settings/x")
    eq(u[5], "gemini://h/x")
    eq(u[6], "gemini://h2/x")
    eq(u[7], "gemini://h2/y?q")
    eq(u[8], "gemini://h/settings/avatar/V5XoC8e7xT")
    eq(u[9], "gemini://h/settings/avatar/a//b")
    eq(u[10], "gemini://h/settings/")
  end)

  it("resolves links against a base with a port and a query", function()
    reset()
    responses = { { "20 text/gemini",
      "=> ?y a new query",
      "=> x the query is dropped",
      "=> #f the query stays",
    } }
    local w = run("h:1966/p?q")

    eq(w.gem.links[1].url, "gemini://h:1966/p?y")
    eq(w.gem.links[2].url, "gemini://h:1966/x")
    eq(w.gem.links[3].url, "gemini://h:1966/p?q")
  end)

  it("resolves relative redirects against the request", function()
    reset()
    responses = { { "30 /new" }, { "20 text/gemini", "ok" } }
    run("h/dir/old?q")
    eq(requests[2], "gemini://h/new\r\n",
      "an absolute-path redirect drops the query")

    reset()
    responses = { { "30 next" }, { "20 text/gemini", "ok" } }
    run("h/dir/page")
    eq(requests[2], "gemini://h/dir/next\r\n", "a relative redirect")

    reset()
    responses = { { "30 ?y" }, { "20 text/gemini", "ok" } }
    run("h/search?x")
    eq(requests[2], "gemini://h/search?y\r\n", "a query-only redirect")
  end)

  it("back and forward walk the history", function()
    local w = run("h/a")
    ext.gemini({ output = function() return w end }, "h/b")
    pump(w)
    ext.gemini({ output = function() return w end }, "h/c")
    pump(w)
    eq(#w.gem.hist, 3)
    eq(w.gem.pos, 3)
    eq(w.cmdline, "Back Save Scroll")

    ok(w.cmd.Back(w))
    pump(w)
    eq(w.gem.url, "gemini://h/b")
    eq(w.cmdline, "Back Forward Save Scroll")
    ok(w.cmd.Forward(w))
    pump(w)
    eq(w.gem.url, "gemini://h/c")
    ok(w.cmd.Back(w))
    pump(w)
    eq(w.gem.pos, 2)
    ok(w.cmd.Back(w))
    eq(w.gem.pos, 1)
    ok(w.cmd.Back(w), "already at the start")
    eq(w.gem.pos, 1)

    ext.gemini({ output = function() return w end }, "h/d")
    pump(w)
    eq(#w.gem.hist, 2, "the forward entries are dropped")
    eq(w.gem.hist[2], "gemini://h/d")
  end)

  it("alt+left and alt+right walk the history", function()
    local w = run("h/a")
    ext.gemini({ output = function() return w end }, "h/b")
    pump(w)
    local asked = 0
    w.run = function()
      asked = asked + 1
      return {}
    end
    with_alt(function()
      w:keydown_event("left")
      eq(w.gem.pos, 1)
      w:keydown_event("right")
      eq(w.gem.pos, 2)
    end)
    eq(asked, 2)
    w:keydown_event("F5")
    eq(asked, 2, "without alt the base handler runs")
  end)

  it("a 10 response prompts and the answer is sent as the query", function()
    reset()
    responses = { { "10 Введите запрос" }, { "20 text/gemini", "got" } }
    local w = run("h/search")
    eq(requests[1], "gemini://h/search\r\n")
    eq(w:gettext(),
      "gemini://h/search\n[10 Введите запрос]\n? Введите запрос ")
    eq(w.gem.input.url, "gemini://h/search")
    eq(w.gem.input.pos, #w.buf.text + 1)
    eq(w.buf.cur, w.gem.input.pos, "the cursor waits for the answer")

    w.buf:input("привет мир")
    w:newline()
    pump(w)
    eq(requests[2],
      "gemini://h/search?%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20%D0%BC%D0%B8%D1%80\r\n")
    eq(w.gem.input, nil)
    ok(w:gettext():find("got", 1, true))
  end)

  it("the answer replaces an existing query", function()
    reset()
    responses = { { "10 ask" }, { "20 text/gemini" } }
    local w = run("h/search?old")
    w.buf:input("new")
    w:newline()
    pump(w)
    eq(requests[2], "gemini://h/search?new\r\n")
  end)

  it("return before the prompt inserts a newline", function()
    responses = { { "10 ask" } }
    local w = run("h/x")
    w.visible = function() end
    w.make_epos = function() end
    w.rows = 0
    w.buf.cur = 1
    w:newline()
    eq(w:gettext():sub(1, 1), "\n")
    ok(w.gem.input, "the prompt is still pending")
  end)

  it("shift+return makes the answer multiline", function()
    reset()
    responses = { { "10 ask" }, { "20 text/gemini" } }
    local w = run("h/search")

    w.buf:input("one")
    with_shift(function()
      w:newline()
    end)
    eq(#requests, 1, "shift+return sends nothing")
    eq(w:gettext():sub(-1), "\n", "the answer got a new line")
    w.buf:input("two")
    w:newline()
    pump(w)
    eq(requests[2], "gemini://h/search?one%0Atwo\r\n")
  end)

  it("a trailing newline is not sent", function()
    reset()
    responses = { { "10 ask" }, { "20 text/gemini" } }
    local w = run("h/search")

    w.buf:input("x")
    with_shift(function()
      w:newline()
    end)
    w:newline()
    pump(w)
    eq(requests[2], "gemini://h/search?x\r\n")
  end)

  it("Get re-fetches the current page", function()
    reset()
    responses = { { "20 text/gemini", "one" }, { "20 text/gemini", "two" } }
    local w = run("h/a")
    ok(w:gettext():find("one", 1, true))
    ok(w:Get())
    pump(w)
    ok(w:gettext():find("two", 1, true))
    eq(requests[1], requests[2], "the same page is requested again")
    eq(#w.gem.hist, 1, "a reload does not add a history entry")
    eq(w.gem.pos, 1)
  end)

  it("a 60 response offers a certificate and retries", function()
    reset()
    responses = { { "60 Certificate required" },
      { "20 text/gemini", "welcome" } }
    local files = {}
    with_certs(files, function()
      local w = run("h/page")

      eq(#made, 0, "nothing is made before the answer")
      eq(w.gem.cert.host, "h")
      ok(w:gettext():find("requires a client certificate", 1, true),
        "the offer is shown")
      w:newline()
      pump(w)
      eq(#made, 1)
      eq(made[1], "h")
      eq(dials[2][4], "CRT h", "the certificate is sent on the retry")
      eq(dials[2][5], "KEY h")
      eq(w.gem.cert, nil)
      ok(w:gettext():find("welcome", 1, true))
      ok(files[h_crt] ~= nil, "the certificate is saved")
      ok(files[h_key] ~= nil, "the key is saved")
    end)
  end)

  it("a stored certificate is sent to its host", function()
    reset()
    responses = { { "20 text/gemini", "ok" } }
    with_certs({ [h_crt] = "CRT", [h_key] = "KEY" }, function()
      run("h/x")
      eq(dials[1][4], "CRT")
      eq(dials[1][5], "KEY")
      eq(#made, 0, "no new certificate is made")
    end)
  end)

  it("a used certificate is not offered again on 60", function()
    reset()
    responses = { { "60 still needed" } }
    with_certs({ [h_crt] = "CRT", [h_key] = "KEY" }, function()
      local w = run("h/x")

      eq(w.gem.cert, nil, "no offer when the certificate is already used")
      ok(w:gettext():find("already in use", 1, true))
    end)
  end)

  it("61 and 62 responses are explained", function()
    reset()
    responses = { { "61 not authorised" }, { "62 invalid" } }
    local w = run("h/a")
    ok(w:gettext():find("does not authorise", 1, true))
    local w2 = run("h/b")
    ok(w2:gettext():find("not valid", 1, true))
  end)

  it("a gemini window dumps and restores url, history and input", function()
    local w = page("=> gemini://h/a one\n", "gemini://h/x", {
      hist = { "gemini://h/a", "gemini://h/x" },
      pos = 2,
      input = { url = "gemini://h/x", pos = 8 },
    })
    eq(#w.gem.links, 1)
    eq(w.gem.links[1].url, "gemini://h/a")
    eq(w.cmdline, "Back Save Scroll")

    local d = w:dump()
    eq(d.type, "gemini")
    eq(d.url, "gemini://h/x")
    eq(d.pos, 2)
    eq(d.hist[1], "gemini://h/a")
    eq(d.input.pos, 8)

    local w2 = win.kinds.gemini(fake_frame(), d, 1)
    eq(w2.gem.url, "gemini://h/x")
    eq(w2.gem.pos, 2)
    eq(w2.gem.input.url, "gemini://h/x")
    eq(w2.cmdline, "Back Save Scroll")
    eq(w2:dump().hist[1], "gemini://h/a")
  end)

  it("fetches a gopher menu and makes links of its items", function()
    reset()
    responses = { {
      "1Floodgap Home\t/\tgopher.floodgap.com\t70",
      "iHello there\tfake\t(fake)\t0",
      "0Phlog\t/phlog\tgopher.floodgap.com\t70",
      "1Search\t/v2/vs\tgopher.floodgap.com\t70",
      "1Gopher+ item\t/plus\th2\t7070\t+",
      "1Local\t/local\t(NULL)\t0",
      ".",
    } }
    local w = run("gopher://gopher.floodgap.com")
    eq(requests[1], "\r\n", "the root menu selector is empty")
    eq(dials[1][1], "gopher.floodgap.com")
    eq(dials[1][2], 70)
    eq(w.gem.url, "gopher://gopher.floodgap.com")
    eq(#w.gem.links, 5, "an info line is not a link")
    eq(w.gem.links[1].url, "gopher://gopher.floodgap.com/1/")
    eq(w.gem.links[2].url, "gopher://gopher.floodgap.com/0/phlog")
    eq(w.gem.links[3].url, "gopher://gopher.floodgap.com/1/v2/vs")
    eq(w.gem.links[4].url, "gopher://h2:7070/1/plus",
      "a gopher+ attribute is ignored")
    eq(w.gem.links[5].url, "gopher://gopher.floodgap.com/1/local",
      "(NULL) host and 0 port mean the current ones")
    local t = w:gettext()
    ok(t:find("=> /1/ Floodgap Home", 1, true),
      "a link of the same server is a short path")
    ok(t:find("=> /1/v2/vs Search", 1, true))
    ok(t:find("=> //h2:7070/1/plus Gopher+ item", 1, true),
      "another server of the same scheme is a network path")
    ok(w:gettext():find("Hello there", 1, true))
    ok(not w:gettext():find("fake", 1, true))
  end)

  it("only the explicit gophers scheme means tls", function()
    reset()
    responses = { { "." } }
    run("gopher://h:443/1")
    eq(dials[1][2], 443)
    eq(dials[1][3], nil, "a plain page on 443 stays plain")

    reset()
    responses = { { "." } }
    run("gopher://h:433/1")
    eq(dials[1][2], 433)
    eq(dials[1][3], nil, "a plain page on 433 stays plain")

    reset()
    responses = { { "1Ssl\t/about\th\t433", "." } }
    local w = run("gopher://h:70/1")
    eq(w.gem.links[1].url, "gopher://h:433/1/about",
      "a plain page gives plain items")

    reset()
    responses = { { "." } }
    run("gophers://h:433/1")
    eq(dials[1][2], 433)
    eq(dials[1][3], "h", "the explicit gophers scheme means tls")
  end)

  it("gophers:// is gopher over tls", function()
    reset()
    responses = { { "1Same\t/same\th\t307",
      "1Elsewhere\t/other\th2\t70",
      "0A file\t/file\th\t307", "." } }
    local w = run("gophers://h")
    eq(dials[1][1], "h")
    eq(dials[1][2], 307, "the gophers default port")
    eq(dials[1][3], "h", "the tls host is the gopher host")
    eq(w.gem.url, "gophers://h")
    eq(w.gem.links[1].url, "gophers://h/1/same",
      "the same server of a gophers page keeps tls")
    eq(w.gem.links[2].url, "gopher://h2/1/other",
      "another server is plain unless its port says otherwise")
    eq(w.gem.links[3].url, "gophers://h/0/file")
    local t = w:gettext()
    ok(t:find("=> /1/same Same", 1, true),
      "the same server of a gophers page stays a short path")
    ok(t:find("=> gopher://h2/1/other Elsewhere", 1, true),
      "another scheme needs the full url")

    reset()
    responses = { { "." } }
    run("gophers://h:307/1")
    eq(dials[1][2], 307)
    eq(dials[1][3], "h")
  end)

  it("resolves the selectors of a gopher menu", function()
    reset()
    responses = { {
      "0Dockerfile\t/hist/../coding/x.ssem\tygrex.ru\t70\t+",
      "1Up\t../\tygrex.ru\t70",
      "1Sibling\tother/\tygrex.ru\t70",
      "1Root\t\tother.host\t70",
      ".",
    } }
    local w = run("gopher://ygrex.ru/1/hist/")
    eq(requests[1], "/hist/\r\n")
    eq(#w.gem.links, 4)
    eq(w.gem.links[1].url, "gopher://ygrex.ru/0/coding/x.ssem",
      "the dot segments are removed")
    eq(w.gem.links[2].url, "gopher://ygrex.ru/1/",
      "a relative selector goes up")
    eq(w.gem.links[3].url, "gopher://ygrex.ru/1/hist/other/",
      "a relative selector joins the page selector")
    eq(w.gem.links[4].url, "gopher://other.host/1",
      "an empty selector is not the current directory")
    local t = w:gettext()
    ok(t:find("=> /0/coding/x.ssem Dockerfile", 1, true))
    ok(t:find("=> //other.host/1 Root", 1, true))
  end)

  it("a gopher URL item is left to uri", function()
    reset()
    responses = { { "hGitHub\t/URL:https://github.com/x\tygrex.ru\t70",
      "hzxnet\tURL:http://zxnet.co.uk/\tzxnet.co.uk\t70", "." } }
    local w = run("gopher://ygrex.ru/1")
    eq(#w.gem.links, 2)
    eq(w.gem.links[1].url, "https://github.com/x")
    eq(w.gem.links[2].url, "http://zxnet.co.uk/",
      "the selector may have no leading slash")
    local asked, executed = {}, {}
    w.x, w.y, w.w, w.h = 0, 0, 100, 100
    w.run = function(_, f)
      table.insert(asked, f)
      return {}
    end
    w.exec = function(_, t) table.insert(executed, t) end
    w.off2cur = function() return 3 end
    w:event('mouseup', 'middle', 20, 5)
    eq(#asked, 0, "http(s) is not fetched over gopher")
    eq(#executed, 1, "uri.lua opens it")
  end)

  it("shows a gopher text file as it is", function()
    reset()
    responses = { { "hello", "world" } }
    local w = run("gopher://h/0/file")
    eq(requests[1], "/file\r\n")
    eq(#w.gem.links, 0)
    ok(w:gettext():find("hello", 1, true))
    ok(w:gettext():find("world", 1, true))
  end)

  it("a gopher search asks for the query and sends it after a tab", function()
    reset()
    responses = { { "1Results\t/search\th\t70", "." } }
    local w = run("gopher://h/7/v2/vs")
    eq(#requests, 0, "nothing is sent before the answer")
    eq(w.gem.input.url, "gopher://h/7/v2/vs")
    ok(w:gettext():find("search:", 1, true))
    w.buf:input("hello world")
    w:newline()
    pump(w)
    eq(requests[1], "/v2/vs\thello world\r\n")
    eq(w.gem.input, nil)
  end)

  it("closing a window stops the request in flight", function()
    local w = page("", "gemini://h/x")
    local closed = 0
    local rec
    w.run = function(_, fn)
      rec = { coroutine.create(fn), w }
      table.insert(w.co, rec)
      return rec
    end
    ext.gemini({ output = function() return w end }, "h/x")
    w.gem.sock = { close = function() closed = closed + 1 end }
    w:killproc()
    eq(closed, 1)
    eq(w.gem.sock, nil)
  end)

  it("a gopher link keeps its scheme when followed", function()
    reset()
    responses = { { "hello" } }
    local w = page("=> gopher://h/0/file a file\n", "gemini://h/page")
    w.x, w.y, w.w, w.h = 0, 0, 100, 100
    w.off2cur = function() return 3 end
    w.exec = function() end
    ok(w:event('mouseup', 'middle', 20, 5))
    pump(w)
    eq(requests[1], "/file\r\n")
    eq(w.gem.url, "gopher://h/0/file")
  end)

  it("Save downloads the link at the cursor", function()
    reset()
    responses = { { "20 text/plain", "BODY" } }
    local w = page("=> gemini://h/0/file a file\n", "gemini://h/x")
    with_save(function(files)
      w.cmd.Save(w)
      pump(w)
      eq(requests[1], "gemini://h/0/file\r\n")
      eq(dials[1][1], "h")
      eq(files["file"], "BODY\r\n", "the response header is not saved")
    end)
    ok(w:gettext():find("saved file", 1, true))
  end)

  it("Save takes a gopher link and an explicit name", function()
    reset()
    responses = { { "hello", "world" } }
    local w = page("=> gopher://h/0/file a file\n", "gopher://h/1")
    with_save(function(files)
      w.cmd.Save(w, "out.bin")
      pump(w)
      eq(requests[1], "/file\r\n")
      eq(dials[1][2], 70)
      eq(files["out.bin"], "hello\r\nworld\r\n")
    end)
  end)

  it("Save reports a bad gemini status", function()
    reset()
    responses = { { "51 not found" } }
    local w = page("=> gemini://h/missing x\n", "gemini://h/x")
    with_save(function()
      w.cmd.Save(w)
      pump(w)
      ok(w:gettext():find("[51 not found]", 1, true))
    end)
  end)

  it("Save without a link at the cursor says so", function()
    reset()
    local w = page("plain text\n", "gemini://h/x")
    w.cmd.Save(w)
    eq(#requests, 0)
    ok(w:gettext():find("no link at the cursor", 1, true))
  end)
end)

-- the tests above run as the file loads: do not leak the fake dial
sock.dial = real_dial
