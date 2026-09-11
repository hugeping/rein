local win = require "red/win"

-- minimal window good enough for colorize(): no geometry/font needed
local function make(text, conf)
  local w = win:new("test")
  w.buf:input(text)
  w.buf.cur = 1
  w.pos = 1
  w.cols = 1000
  w.rows = 10
  w.conf = conf or { syntax = 'lua', colorize_win = 16 }
  return w
end

local function count_process(c)
  local n = 0
  local orig = c.process
  c.process = function(self, ...)
    n = n + 1
    return orig(self, ...)
  end
  return function() return n end
end

describe("win:colorize", function()
  it("colors the visible text and clears dirty", function()
    local w = make("local x = 1")
    local c = w:colorize()
    ok(c, "colorizer created")
    ok(c.pos >= w.epos, "colored up to epos")
    eq(c.dirty, false, "dirty cleared")
    ok(c.cols[1] ~= nil, "first char colored")
    ok(c.cols[w.epos - 1] ~= nil, "last visible char colored")
  end)

  it("skips work when nothing changed", function()
    local w = make("local x = 1")
    local c = w:colorize()
    local calls = count_process(c)
    local c2 = w:colorize()
    eq(c2, c, "same colorizer")
    eq(calls(), 0, "no reprocessing")
    eq(c.cols, c2.cols, "same cols table")
  end)

  it("re-colors after dirty and clears the flag", function()
    local text = ("local x = 1\n"):rep(100)
    local w = make(text)
    w.pos = 500
    local c = w:colorize()
    ok(c.saved, "anchor state saved")
    local calls = count_process(c)
    c.dirty = true
    local c2 = w:colorize()
    eq(c2, c, "same colorizer resumed")
    ok(calls() > 0, "reprocessed after dirty")
    eq(c.dirty, false, "dirty cleared")
  end)

  it("picks up an edit at the top of the file", function()
    local w = make("local x")
    w:colorize()
    w.buf:set("if x")
    w.colorizer.dirty = true
    w:colorize()
    ok(w.colorizer.cols[1] ~= nil, "first char colored")
    ne(w.colorizer.cols[1], w.colorizer.cols[4],
      "keyword differs from identifier after edit")
  end)

  it("extends coloring when scrolled down", function()
    local w = make("local a\nlocal b\nlocal c")
    w.rows = 1
    local c = w:colorize()
    local first_epos = w.epos
    local calls = count_process(c)
    w.pos = first_epos + 1
    w:colorize()
    ok(calls() > 0, "colored more after scroll")
    ok(c.pos >= w.epos, "colored up to the new epos")
  end)
end)
