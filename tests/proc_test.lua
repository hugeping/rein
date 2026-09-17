local win = require "red/win"

describe("proc extensions", function()
  it("each file of red/proc exports a table of procedures", function()
    for _, n in ipairs { "gemini", "grep", "dump", "dos2unix",
      "fmt", "par", "win", "cat", "indent", "shell", "buf" } do
      local t = require("red/proc/" .. n)
      eq(type(t), "table", n)
      ok(next(t), n .. " exports a procedure")
    end
  end)

  it("win makes a pseudo shell window", function()
    local w = win:new("+win")
    w.frame = { update = function() end }
    w.visible = function() end
    ok(require("red/proc/win").win({ output = function() return w end }))
    eq(w.cmdline, "Noscroll")
    eq(w.scroll_mode, true)
    eq(w:gettext():find("$ ", 1, true), 1, "the prompt is printed")
    ok(w.shell, "the window is a shell")
  end)

  it("cat inserts a file at the cursor", function()
    local w = win:new("t.txt")
    w.visible = function() end
    w.make_epos = function() end
    w.path = function(_, f) return f end
    ok(require("red/proc/cat").cat(w, "data/lib/red/proc/cat.lua"))
    ok(w:gettext():find("A proc extension", 1, true), "the file is inserted")
  end)

  it("indent indents and unindents with tabs", function()
    local ext = require "red/proc/indent"
    local w = win:new("t.txt")
    w.visible = function() end
    w:set("a\nb\n")
    ok(ext["i+"](w))
    eq(w:gettext(), "\ta\n\tb\n")
    ok(ext["i-"](w))
    eq(w:gettext(), "a\nb\n")
  end)

  it("shell exports the run commands", function()
    local ext = require "red/proc/shell"
    for _, k in ipairs { "!", "@", "<", ">", "|" } do
      eq(type(ext[k]), "function", k)
    end
    eq(ext["!"]({}, ""), nil, "an empty command does nothing")
  end)

  it("buf procs work on the buffer", function()
    local ext = require "red/proc/buf"
    local w = win:new("t.txt")
    w.visible = function() end
    w:set("one two\nthree two\n")
    w.buf:setsel(1, #w.buf.text + 1)
    ok(ext.sub(w, "/two/2/"))
    eq(w:gettext(), "one 2\nthree 2\n")

    local w2 = win:new("t2.txt")
    w2.visible = function() end
    w2.frame = { main = function() return {} end }
    w2:set("A\nB\n")
    w2:cur(1)
    ok(ext.Codepoint(w2))
    eq(w2:gettext():sub(1, 5), " 0x41")
    ok(ext.Line(w2))
    ok(w2:gettext():find(" :1", 1, true))
    ok(ext.Clear(w2))
    eq(w2:gettext(), "")
  end)

  it("dos2unix strips the carriage returns", function()
    local w = win:new("t.txt")
    w.visible = function() end
    w:set("a\r\nb\r\n")
    require("red/proc/dos2unix").dos2unix(w)
    eq(w:gettext(), "a\nb\n")
  end)
end)
