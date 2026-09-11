local menu = require "red/menu"
local win = require "red/win"

describe("menu", function()
  it("exec dispatches to the window command first", function()
    local m = menu:new()
    local called = {}
    local w = { cmd = { Put = function() called.put = true; return true end } }
    m.winmenu = function() return w end
    m.cmd = {}
    ok(menu.exec(m, "Put"))
    ok(called.put)
  end)

  it("exec falls back to the menu command", function()
    local m = menu:new()
    local called = {}
    m.winmenu = function() return nil end
    m.cmd = { New = function() called.new = true; return true end }
    ok(menu.exec(m, "New"))
    ok(called.new)
  end)

  it("exec slices the argument after the command", function()
    local m = menu:new()
    local got
    m.winmenu = function() return nil end
    m.cmd = { Tab = function(_, arg) got = arg; return true end }
    ok(menu.exec(m, "Tab 4"))
    eq(got, "4")
  end)
end)
