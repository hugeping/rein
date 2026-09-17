local win = require "red/win"
local ext = require "red/proc/edit"

-- run the script on a fresh window; return the text and the messages
local function edit(text, script)
  local w = win:new("t.txt")
  local errs = {}

  w.frame = {
    update = function() end,
    err = function(_, fmt, ...)
      table.insert(errs, string.format(fmt, ...))
    end,
  }
  w:set(text)
  ok(ext.Edit(w, script))
  return w:gettext(), errs, w
end

describe("edit", function()
  it("s replaces the first match of the range", function()
    eq(edit("one two three\n", ",s/two/TWO/"), "one TWO three\n")
  end)

  it("s with g replaces every match", function()
    eq(edit("a x b x c\n", ",s/x/-/g"), "a - b - c\n")
  end)

  it("s2 replaces the second match", function()
    eq(edit("x x x\n", ",s2/x/y/"), "x y x\n")
  end)

  it("s uses classes and repetitions", function()
    eq(edit("n1 n22 n333\n", ",s/n[0-9]+/N/g"), "N N N\n")
  end)

  it("s understands groups and &", function()
    eq(edit("ab cd\n", ",s/(a)(b)/\\2\\1/"), "ba cd\n")
    eq(edit("ab cd\n", ",s/ab/[&]/"), "[ab] cd\n")
  end)

  it("alternation takes the longest branch, as in sam", function()
    eq(edit("ab\n", ",s/a|ab/X/"), "X\n")
    eq(edit("ab\n", ",s/b|ab/X/"), "X\n")
  end)

  it("does not backtrack exponentially", function()
    eq(edit(string.rep("a", 20) .. "\n", ",x/(a|a)*$c/ d"),
      string.rep("a", 20) .. "\n")
  end)

  it("an empty regexp uses the last one", function()
    eq(edit("x x\n", ",s/x/1/\n,s//2/"), "1 2\n")
  end)

  it("x changes every match", function()
    eq(edit("a foo b foo\n", ",x/foo/ c/bar/"), "a bar b bar\n")
    eq(edit("a foo b foo\n", ",x/foo/ d"), "a  b \n")
  end)

  it("g and v run the command conditionally", function()
    eq(edit("a\nb\n", ",g/a/d"), "")
    eq(edit("a\nb\n", ",v/a/d"), "a\nb\n")
    eq(edit("a\nb\n", ",v/zzz/d"), "")
  end)

  it("y addresses the text between the matches", function()
    eq(edit("axbxc", ",y/x/ c/-/"), "-x-x-")
  end)

  it("line and relative addresses", function()
    eq(edit("a\nb\nc\n", "2d"), "a\nc\n")
    eq(edit("a\nb\nc\n", "2,3d"), "a\n")
    eq(edit("a\nb\nc\n", "1+1d"), "a\nc\n")
    eq(edit("a\nb\nc\n", "1a/X/"), "a\nXb\nc\n")
    eq(edit("a\nb\nc\n", "$a/X/"), "a\nb\nc\nX")
    eq(edit("a\nb\nc\n", ",/b/d"), "\nc\n")
    eq(edit("a\nb\nc\n", "/b/d"), "a\n\nc\n")
    eq(edit("a\nb\nc\n", "?c?d"), "a\nb\n\n")
    eq(edit("a\nb\nc\n", "#1,#2d"), "ab\nc\n")
  end)

  it("the + may be elided between addresses", function()
    -- 1 2 is 1+2: the second line from the end of line 1
    eq(edit("a\nb\nc\n", "1 2d"), "a\nb\n")
    eq(edit("a\nb\nc\n", "2,3 d"), "a\n")
    -- 1 /rein/ is 1+/rein/: just the match after the end of line 1
    local _, _, w = edit("a\nb rein\n", "1 /rein/")
    local sel = w.buf:getsel()

    eq(sel.s, 5)
    eq(sel.e, 9)
  end)

  it("m and t move and copy the range", function()
    eq(edit("b\na\n", ",x/a/ m 0"), "ab\n\n")
    eq(edit("b\na\n", ",x/a/ t 0"), "ab\na\n")
  end)

  it("a i c take following lines ended by a dot", function()
    eq(edit("a\n", "1a\nx\ny\n.\n"), "a\nx\ny\n")
    eq(edit("a\nb\n", "2c\nZ\n.\n"), "a\nZ\n")
    eq(edit("a\n", "1i\nX\n.\n"), "X\na\n")
  end)

  it("p and = print to the errors window", function()
    local _, errs = edit("a\nb\n", ",p")
    eq(table.concat(errs, "|"), "a\nb\n")

    local _, errs2 = edit("a\nb\n", "2=")
    eq(table.concat(errs2, "|"), "t.txt:2")

    local _, errs3 = edit("a\nb\n", "2=#")
    eq(table.concat(errs3, "|"), "t.txt:#2,#4") -- the name, as in acme

    local _, errs4 = edit("a\nb\n", "2=+")
    eq(table.concat(errs4, "|"), "t.txt:2+#0")
  end)

  it("dot is set to the modified range, as in sam", function()
    local _, _, w = edit("one two\n", ",s/two/2/")
    local sel = w.buf:getsel()

    eq(sel.s, 1)
    eq(sel.e, 7) -- the whole range, shortened by the delta
  end)

  it("errors are reported and stop the script", function()
    local text, errs = edit("a\n", ",s/zzz/x/")
    eq(text, "a\n")
    ok(errs[1] and errs[1]:find("no match", 1, true))

    local _, errs2 = edit("a\n", ",s/[a/x/")
    ok(errs2[1] and errs2[1]:find("bad class", 1, true))

    local _, errs3 = edit("a\n", "1d junk")
    ok(errs3[1] and errs3[1]:find("unexpected", 1, true))

    local _, errs4 = edit("a\n", "1z")
    ok(errs4[1] and errs4[1]:find("unknown command", 1, true))
  end)

  it("edits the window of the menu it is run from", function()
    local w = win:new("t.txt")
    local errs = {}

    w.frame = { update = function() end,
      err = function(_, fmt, ...) table.insert(errs, string.format(fmt, ...)) end }
    w:set("one two\n")
    local menu = { data = function() return w end, frame = w.frame }

    ok(ext.Edit(menu, ",s/two/2/"))
    eq(w:gettext(), "one 2\n")
  end)

  it("a bare command acts on dot only, as in sam", function()
    local w = win:new("t.txt")
    local errs = {}

    w.frame = { update = function() end,
      err = function(_, fmt, ...) table.insert(errs, string.format(fmt, ...)) end }
    w:set("rein rein\n")
    w.buf.cur = 1
    ok(ext.Edit(w, "s/rein/X/")) -- no selection: dot is a point
    eq(w:gettext(), "rein rein\n")
    ok(errs[1] and errs[1]:find("no match", 1, true))

    local w2 = win:new("t.txt")

    w2.frame = { update = function() end, err = function() end }
    w2:set("rein rein\n")
    w2.buf:setsel(6, 10) -- the second rein: dot is the selection
    ok(ext.Edit(w2, "s/rein/X/"))
    eq(w2:gettext(), "rein X\n")
  end)

  it("repeated /regexp/ searches sequentially", function()
    local w = win:new("t.txt")
    local errs = {}

    w.frame = { update = function() end,
      err = function(_, fmt, ...) table.insert(errs, string.format(fmt, ...)) end }
    w:set("one two\nthree two\n")

    ok(ext.Edit(w, "/two/"))
    local sel = w.buf:getsel()

    eq(sel.s, 5)
    eq(sel.e, 8)
    ok(ext.Edit(w, "/two/")) -- from the selection: the next match
    sel = w.buf:getsel()
    eq(sel.s, 15)
    eq(sel.e, 18)
    ok(ext.Edit(w, "//")) -- the empty regexp: the same search, wraps
    sel = w.buf:getsel()
    eq(sel.s, 5)
    eq(sel.e, 8)
    eq(#errs, 0)
  end)

  it("the whole Edit is one undo step", function()
    local w = win:new("t.txt")

    w.frame = { update = function() end, err = function() end }
    w.visible = function() end
    w.make_epos = function() end
    w.rows = 0
    w:set("rein one\nrein two\n")
    ok(ext.Edit(w, ",x/rein/ c/X/"))
    eq(w:gettext(), "X one\nX two\n")
    w:undo()
    eq(w:gettext(), "rein one\nrein two\n")
  end)

  it("search and replace start at the cursor", function()
    local w = win:new("t.txt")
    local errs = {}

    w.frame = { update = function() end,
      err = function(_, fmt, ...) table.insert(errs, string.format(fmt, ...)) end }
    w:set("one rein\nrein two\n")
    w.buf.cur = 10 -- the beginning of line 2
    ok(ext.Edit(w, "/rein/ s//X/"))
    eq(w:gettext(), "one rein\nX two\n")
    ok(ext.Edit(w, "/rein/ s//X/")) -- on from the replacement, wraps
    eq(w:gettext(), "one X\nX two\n")
    eq(#errs, 0)
  end)

  it("an empty match after a match is not repeated, as in sam", function()
    eq(edit("aa", ",x/a*/ c/X/"), "X")
    eq(edit("aa", ",s/a*/X/g"), "X")
  end)

  it("a backslash in a replacement quotes the next character", function()
    eq(edit("a\n", ",s/a/\\&/"), "&\n")
    eq(edit("ab\n", ",s/(a)(b)/\\2\\1/"), "ba\n")
  end)

  it("m refuses an overlapping move", function()
    local w = win:new("t.txt")
    local errs = {}

    w.frame = { update = function() end,
      err = function(_, fmt, ...) table.insert(errs, string.format(fmt, ...)) end }
    w:set("abcd\n")
    ok(ext.Edit(w, ",x/bcd/ m /c/"))
    eq(w:gettext(), "abcd\n")
    ok(errs[1] and errs[1]:find("overlaps", 1, true))

    ok(ext.Edit(w, ",x/bcd/ m /bcd/")) -- move to self
    eq(w:gettext(), "abcd\n")
  end)

  it("relative lines count from the line of the address", function()
    eq(edit("ab\ncd\n", "/b/+1d"), "ab\n") -- the line after "b"
    eq(edit("ab\ncd\n", "/c/-1d"), "cd\n") -- the line before "c"
    eq(edit("ab\ncd\n", ",/b/+1d"), "") -- from the start to it
  end)

  it("no window: reported", function()
    local errs = {}
    local menu = { frame = { err = function(_, fmt, ...)
      table.insert(errs, string.format(fmt, ...)) end },
      data = function() return nil end }

    ok(ext.Edit(menu, ",s/a/b/"))
    ok(errs[1] and errs[1]:find("no window", 1, true))
  end)

  it("no command: nothing happens", function()
    local w = win:new("t.txt")
    local errs = {}

    w.frame = { err = function(_, fmt, ...) table.insert(errs, string.format(fmt, ...)) end }
    ok(ext.Edit(w, ""))
    ok(errs[1] and errs[1]:find("no command", 1, true))
  end)
end)
