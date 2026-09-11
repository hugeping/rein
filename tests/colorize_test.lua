local win = require "red/win"
local scheme = require "red/syntax/scheme"

-- minimal window good enough for colorize(): no geometry/font needed
local function make(text, conf)
  local w = win:new("test")
  w.buf:input(text)
  w.buf.cur = 1
  w.pos = 1
  w.cols = 1000
  w.rows = 10
  w.conf = conf or { syntax = 'lua', colorize_checkpoint = 64 }
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
    ok(#c.checkpoints > 1, "checkpoints recorded")
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

  it("picks up a context change above the viewport", function()
    local text = ("x = 1\n"):rep(300)
    local w = make(text)
    w.rows = 5
    w.pos = 1500
    w:colorize()
    local v = w.pos + 5
    ne(w.colorizer.cols[v], scheme.comment, "code before the edit")
    -- open a block comment at position 100, above the viewport
    local ins = utf.chars("--[[")
    for i = #ins, 1, -1 do
      table.insert(w.buf.text, 100, ins[i])
    end
    w.buf:mark(100)
    w.colorizer.dirty = true
    w:colorize()
    eq(w.colorizer.cols[v + #ins], scheme.comment,
      "comment color after the edit above")
  end)

  it("re-lexes only from the last checkpoint after an edit", function()
    local text = ("x = 1\n"):rep(300)
    local w = make(text)
    w.rows = 5
    w.pos = 1500
    local c = w:colorize()
    local calls = count_process(c)
    table.insert(w.buf.text, w.pos, 'y')
    w.buf:mark(w.pos)
    c.dirty = true
    w:colorize()
    local n = calls()
    ok(n > 0, "reprocessed")
    ok(n < 200, "bounded re-lex, calls=" .. n)
  end)

  it("state restore does not alias the checkpoint stack", function()
    local text = ("--[[ block\n"):rep(50)
    local w = make(text)
    local c = w:colorize()
    local cp = c:state()
    local n = #cp.stack
    c:state(cp)
    c:process(c.pos, #text)
    eq(#cp.stack, n, "checkpoint stack not mutated")
  end)
end)
