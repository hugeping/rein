local buf = require "red/buf"

local function nb(text)
  local b = buf:new("test")
  if text then b:input(text) end
  return b
end

describe("buf", function()
  it("new buffer is empty", function()
    local b = buf:new("x")
    eq(b:gettext(), "")
    eq(#b.text, 0)
  end)

  it("input inserts at cursor", function()
    local b = nb("hello")
    eq(b:gettext(), "hello")
    b.cur = 1
    b:input("X")
    eq(b:gettext(), "Xhello")
  end)

  it("input sets changed flag", function()
    local b = buf:new("x")
    b:input("a")
    eq(b:changed(), true)
  end)

  it("backspace removes previous char", function()
    local b = nb("abc")
    b:backspace()
    eq(b:gettext(), "ab")
  end)

  it("delete removes char at cursor", function()
    local b = nb("abc")
    b.cur = 2
    b:delete()
    eq(b:gettext(), "ac")
  end)

  it("setsel/issel/selrange work", function()
    local b = nb("hello")
    b:setsel(4, 2)
    ok(b:issel())
    local s, e = b:selrange()
    eq(s, 2)
    eq(e, 4)
    eq(b:getseltext(), "el")
  end)

  it("cut removes selection and stores clipboard", function()
    local b = nb("hello world")
    b:setsel(1, 6)
    b:cut()
    eq(b:gettext(), " world")
    eq(b.clipboard, "hello")
  end)

  it("copy keeps text", function()
    local b = nb("hello")
    b:setsel(1, 6)
    b:cut(true)
    eq(b:gettext(), "hello")
    eq(b.clipboard, "hello")
  end)

  it("paste prefers the system clipboard", function()
    local b = nb("ab")
    sys.clipboard("XY")
    b.clipboard = "ZZ"
    b.cur = 2
    b:paste()
    eq(b:gettext(), "aXYb")
    sys._clip = nil
  end)

  it("paste falls back to the buffer clipboard", function()
    local b = nb("ab")
    sys._clip = nil
    b.clipboard = "XY"
    b.cur = 2
    b:paste()
    eq(b:gettext(), "aXYb")
  end)

  it("selpar selects a word", function()
    local b = nb("hello world")
    b.cur = 8
    b:selpar()
    eq(b:getseltext(), "world")
  end)

  it("selpar selects word between delimiters", function()
    local b = nb("one two\nthree four\n")
    b.cur = 3
    b:selpar()
    eq(b:getseltext(), "one")
  end)

  it("selpar selects inside parentheses", function()
    local b = nb("foo(bar)baz")
    b.cur = 5
    b:selpar()
    eq(b:getseltext(), "bar")
  end)

  it("selpar handles nested brackets", function()
    local b = nb("a(b(c)d)e")
    b.cur = 3
    b:selpar()
    eq(b:getseltext(), "b(c)d")
  end)

  it("selpar works from a closing bracket", function()
    local b = nb("foo(bar)baz")
    b.cur = 8
    b:selpar()
    eq(b:getseltext(), "bar")
  end)

  it("selpar selects inside quotes", function()
    local b = nb('x = "hello"')
    b.cur = 6
    b:selpar()
    eq(b:getseltext(), "hello")
  end)

  it("set_keep preserves cursor when appending", function()
    local b = nb("abc")
    b.cur = 3
    b:set_keep("abcd")
    eq(b:gettext(), "abcd")
    eq(b.cur, 3)
  end)

  it("set_keep shifts cursor after insertion before it", function()
    local b = nb("abc")
    b.cur = 4
    b:set_keep("Xabc")
    eq(b:gettext(), "Xabc")
    eq(b.cur, 5)
  end)

  it("set_keep shifts selection", function()
    local b = nb("abc")
    b.cur = 3
    b:set_keep("XXabc", { s = 2, e = 4 })
    local s, e = b:selrange()
    eq(s, 4)
    eq(e, 6)
  end)

  it("search forward finds next occurrence", function()
    local b = nb("abc abc")
    b.cur = 2
    ok(b:search("abc"))
    eq(b.cur, 5)
  end)

  it("search backward finds previous occurrence", function()
    local b = nb("abc abc")
    b.cur = #b.text + 1
    ok(b:search("abc", true))
    eq(b.cur, 5)
  end)

  it("undo restores after input", function()
    local b = nb("abc")
    b:input("d")
    eq(b:gettext(), "abcd")
    b:undo()
    eq(b:gettext(), "abc")
  end)

  it("redo restores after undo", function()
    local b = nb("abc")
    b:input("d")
    b:undo()
    b:redo()
    eq(b:gettext(), "abcd")
  end)

  it("undo restores after backspace", function()
    local b = nb("abc")
    b:backspace()
    eq(b:gettext(), "ab")
    b:undo()
    eq(b:gettext(), "abc")
  end)

  it("undo/redo restores a cut", function()
    local b = nb("hello")
    b:setsel(1, 3)
    b:cut()
    eq(b:gettext(), "llo")
    b:undo()
    eq(b:gettext(), "hello")
    b:redo()
    eq(b:gettext(), "llo")
  end)

  it("undo/redo roundtrip of multiple inputs", function()
    local b = buf:new("x")
    for _, c in ipairs({ "a", "b", "c" }) do b:input(c) end
    eq(b:gettext(), "abc")
    b:undo()
    b:undo()
    b:undo()
    b:redo()
    b:redo()
    b:redo()
    eq(b:gettext(), "abc")
  end)

  it("mark remembers the earliest changed position", function()
    local b = buf:new("t")
    b:input("hello")
    b.changed_from = nil
    b.cur = 3
    b:input("X")
    eq(b.changed_from, 3)
    b.cur = 1
    b:input("Y")
    eq(b.changed_from, 1)
  end)

  it("undo/redo mark the changed position", function()
    local b = buf:new("t")
    b:input("hello")
    b.changed_from = nil
    b:undo()
    eq(b.changed_from, 1)
    b.changed_from = nil
    b:redo()
    eq(b.changed_from, 1)
  end)

  it("cut and backspace mark the changed position", function()
    local b = buf:new("t")
    b:input("hello")
    b.changed_from = nil
    b.cur = 4
    b:backspace()
    eq(b.changed_from, 3)
    b.changed_from = nil
    b:setsel(2, 4)
    b:cut()
    eq(b.changed_from, 2)
  end)

  it("history is trimmed to history_len", function()
    local b = buf:new("x")
    b.history_len = 8
    for _ = 1, 64 do b:input("x") end
    ok(#b.hist <= 8, "history kept " .. #b.hist .. " entries")
  end)
end)
