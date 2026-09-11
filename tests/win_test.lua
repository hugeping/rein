local win = require "red/win"

local function fake_win()
  local w = {
    x = 0, y = 0, w = 100, h = 100,
    calls = {},
    buf = { cur = 1, cx = 0, text = {} },
  }
  setmetatable(w, { __index = win })
  local function rec(name)
    return function(self, ...) table.insert(w.calls, { name, ... }) end
  end
  for _, n in ipairs {
    "left", "right", "up", "down", "movesel", "prevpage", "nextpage",
    "tox", "visible", "cur", "newline", "backspace", "delete",
    "lineend", "linestart", "undo", "redo", "paste", "cut", "compl",
    "kill", "input", "handlekey", "prevline", "nextline",
    "mousedown", "mouseup", "motion",
  } do
    w[n] = rec(n)
  end
  w.getconf = function() return nil end
  w.buf.issel = function() return false end
  w.buf.setsel = function() end
  return w
end

local function called(w, name)
  for _, c in ipairs(w.calls) do
    if c[1] == name then return c end
  end
end

describe("win", function()
  it("event dispatches mousedown with window-local coords", function()
    local w = fake_win()
    w:event("mousedown", "left", 10, 20)
    local c = called(w, "mousedown")
    ok(c, "mousedown called")
    eq(c[2], "left")
    eq(c[3], 10)
    eq(c[4], 20)
  end)

  it("event translates motion to window-local coords", function()
    local w = fake_win()
    w:event("mousemotion", 30, 40)
    local c = called(w, "motion")
    ok(c, "motion called")
    eq(c[2], 30)
    eq(c[3], 40)
  end)

  it("event rejects events outside the window", function()
    local w = fake_win()
    w.x, w.y = 200, 200
    eq(w:event("keydown", "left"), false)
  end)

  it("event scrolls on mousewheel", function()
    local w = fake_win()
    w:event("mousewheel", 3)
    eq(#w.calls, 3)
    eq(w.calls[1][1], "prevline")
  end)

  it("keydown left moves cursor and extends selection", function()
    local w = fake_win()
    w:keydown_event("left")
    ok(called(w, "left"))
    ok(called(w, "movesel"))
  end)

  it("keydown return inserts a newline", function()
    local w = fake_win()
    w:keydown_event("return")
    ok(called(w, "newline"))
  end)

  it("keydown tab inserts a tab by default", function()
    local w = fake_win()
    w:keydown_event("tab")
    local c = called(w, "input")
    ok(c, "input called")
    eq(c[2], "\t")
  end)

  it("keydown unknown key is forwarded to handlekey", function()
    local w = fake_win()
    w:keydown_event("F5")
    local c = called(w, "handlekey")
    ok(c, "handlekey called")
    eq(c[2], "F5")
  end)
end)
