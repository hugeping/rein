local win = require "red/win"
local shell = require "red/shell"

local function fake_win()
  local w = {
    x = 0, y = 0, w = 100, h = 100,
    calls = {},
    buf = { cur = 1, cx = 0, text = {} },
  }
  setmetatable(w, { __index = win })
  local function rec(name)
    return function(_, ...) table.insert(w.calls, { name, ... }) end
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

describe("win dump", function()
  it("dump carries the window state", function()
    local w = win:new("t.txt")
    w:set("hello\nworld\n")
    w.menu = "t.txt | Put"
    w.cwd = "/tmp"
    w.cmdline = "Scroll"
    w.frac = 0.25
    w.scroll_mode = true
    local d = w:dump()
    eq(d.type, "win")
    eq(d.fname, "t.txt")
    eq(d.text, "hello\nworld\n")
    eq(d.line, 1)
    eq(d.menu, "t.txt | Put")
    eq(d.cwd, "/tmp")
    eq(d.cmdline, "Scroll")
    eq(d.frac, 0.25)
    eq(d.scroll, true)
  end)

  it("restore applies a dump entry", function()
    local w = win:new("t.txt")
    w:set("hello\nworld\n")
    w.menu = "t.txt | Put"
    w.cwd = "/tmp"
    w.cmdline = "Scroll"
    w.frac = 0.25
    w.scroll_mode = true
    local d = w:dump()

    local w2 = win:new("other")
    w2:restore(d)
    eq(w2:gettext(), "hello\nworld\n")
    eq(w2.menu, "t.txt | Put")
    eq(w2.cwd, "/tmp")
    eq(w2.cmdline, "Scroll")
    eq(w2.frac, 0.25)
    eq(w2.buf:line_nr(), 1)
    eq(w2.scroll_mode, true)
  end)

  it("the default kind makes the window from a dump entry", function()
    local made
    local fr = { file = function(_, fname, pos, force)
      made = { fname, pos, force }
      return win:new(fname)
    end }
    local d = { type = "win", fname = "t.txt", text = "hi\n" }
    local w = win.kinds.win(fr, d, 3)
    eq(made[1], "t.txt")
    eq(made[2], 3)
    eq(made[3], true)
    eq(w:gettext(), "hi\n")
  end)

  it("shell windows dump their type, history and output pos", function()
    local w = win:new("+win")
    w.frame = { update = function() end }
    shell.win(w)
    w:set("$ ls\nfoo\n")
    w.output_pos = 3
    w.shell.hist = { "ls" }
    local d = w:dump()
    eq(d.type, "shell")
    eq(d.output_pos, 3)
    eq(d.hist[1], "ls")
  end)

  it("the shell kind restores a shell window", function()
    local fr = { update = function() end }
    fr.file = function(_, fname)
      local w = win:new(fname)
      w.frame = fr
      return w
    end
    local d = { type = "shell", fname = "+win", text = "$ ls\nfoo\n",
      output_pos = 3, cmdline = "Noscroll", hist = { "ls" } }
    local w = win.kinds.shell(fr, d, 1)
    ok(w.shell, "shell window")
    eq(w.shell.hist[1], "ls")
    eq(w.output_pos, 3)
    eq(w:gettext(), "$ ls\nfoo\n")
    eq(w.cmdline, "Noscroll")
    eq(w.scroll_mode, true)
  end)
end)
