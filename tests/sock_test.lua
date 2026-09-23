-- Regression test for the sock.lua line iterator: on EOF it must
-- return nil (false would loop forever in a generic for).
local sock = require "sock"

-- wait() yields/sleeps after each successful poll
sys.sleep = function() end

local function fake_sock(chunks)
  local i = 0
  return {
    recv = function(self, n)
      i = i + 1
      if chunks[i] then return chunks[i] end
      return nil, "closed"
    end,
    send = function() return 0 end,
    close = function() end,
  }
end

describe("sock lines", function()
  it("lines(true) yields nil at eof", function()
    net = { dial = function() return fake_sock { "a\nb\n", "c\n" } end }
    local s = sock.dial("example.com", 1965)
    local lines = {}
    local n = 0
    for l in s:lines(true) do
      n = n + 1
      if n > 10 then break end
      table.insert(lines, l)
    end
    eq(n, 3)
    eq(lines[1], "a")
    eq(lines[2], "b")
    eq(lines[3], "c")
  end)

  it("readln(true) reports eof as nil", function()
    net = { dial = function() return fake_sock {} end }
    local s = sock.dial("example.com", 1965)
    local l, e = s:readln(true)
    eq(l, nil)
    eq(e, "closed")
  end)

  it("write returns false when the socket is closed in flight", function()
    -- send() returning 0 means EAGAIN: the write waits, yielding to
    -- the engine; a page left or a window closed in that moment must
    -- stop the write, not crash on the boolean socket
    net = { dial = function() return fake_sock {} end }
    local s = sock.dial("example.com", 70)
    sys.incoroutine = true
    local co = coroutine.create(function() return s:write("abc") end)
    local ok1, r1 = coroutine.resume(co)
    ok(ok1, "the write yields")
    eq(r1, true)
    eq(coroutine.status(co), "suspended")
    s:close()
    local ok2, r2, e2 = coroutine.resume(co)
    eq(ok2, true, "no error on the closed socket")
    eq(r2, false)
    eq(e2, "socket is closed")
    sys.incoroutine = nil
  end)
end)
