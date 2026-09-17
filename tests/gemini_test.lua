local win = require "red/win"
local sock = require "sock"

-- the fake TLS exchange: sock.dial returns canned response lines and
-- the requests are recorded; the extension requires the same sock table
local real_dial = sock.dial
local responses, requests, dials
local function fake_dial(host, port, tls)
  table.insert(dials, { host, port, tls })
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
    close = function() end,
  }
end
sock.dial = fake_dial

local ext = require "red/proc/gemini"

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

local function with_alt(fn)
  local old = input.keydown
  input.keydown = function(m) return m == 'alt' end
  local ok, e = pcall(fn)
  input.keydown = old
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
    w.run = function(_, f) table.insert(asked, f) end
    w.exec = function(_, t) table.insert(executed, t) end
    w.off2cur = function() return 3 end
    ok(w:event('mouseup', 'middle', 5, 5))
    eq(#asked, 1)
    eq(w.gem.hist[#w.gem.hist], "gemini://h/a")
    eq(#executed, 0, "the link click is not executed as a command")
    w.off2cur = function() return 21 end -- the second link line
    ok(w:event('mouseup', 'middle', 5, 5))
    eq(w.gem.hist[#w.gem.hist], "gemini://h/b")
    eq(#executed, 0)
    w.off2cur = function() return 40 end -- end of the page, no link there
    w:event('mouseup', 'middle', 5, 5)
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

  it("back and forward walk the history", function()
    local w = run("h/a")
    ext.gemini({ output = function() return w end }, "h/b")
    pump(w)
    ext.gemini({ output = function() return w end }, "h/c")
    pump(w)
    eq(#w.gem.hist, 3)
    eq(w.gem.pos, 3)
    eq(w.cmdline, "Back Scroll")

    ok(w.cmd.Back(w))
    pump(w)
    eq(w.gem.url, "gemini://h/b")
    eq(w.cmdline, "Back Forward Scroll")
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
    w.run = function() asked = asked + 1 end
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

  it("a gemini window dumps and restores url, history and input", function()
    local w = page("=> gemini://h/a one\n", "gemini://h/x", {
      hist = { "gemini://h/a", "gemini://h/x" },
      pos = 2,
      input = { url = "gemini://h/x", pos = 8 },
    })
    eq(#w.gem.links, 1)
    eq(w.gem.links[1].url, "gemini://h/a")
    eq(w.cmdline, "Back Scroll")

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
    eq(w2.cmdline, "Back Scroll")
    eq(w2:dump().hist[1], "gemini://h/a")
  end)
end)

-- the tests above run as the file loads: do not leak the fake dial
sock.dial = real_dial
