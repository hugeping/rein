local frame = require "red/frame"
local menu = require "red/menu"
local win = require "red/win"
local shell = require "red/shell"

-- In the real app childs[1] is the column menu; keep a placeholder so
-- for_win() enumerates the fake windows correctly.
local function fake_frame()
  local f = frame:new({})
  f.stacked = true
  f.refresh = function() end
  return f
end

describe("frame", function()
  it("menu_tail extracts the command line", function()
    eq(frame.menu_tail("a b | cmd"), "| cmd")
    eq(frame.menu_tail("no pipe"), nil)
    eq(frame.menu_tail(nil), nil)
  end)

  it("menu_set_tail replaces the command line", function()
    eq(frame.menu_set_tail("a b | old", "| new"), "a b | new")
    eq(frame.menu_set_tail("a b", "|new"), "a b |new")
    eq(frame.menu_set_tail(nil, "|new"), "|new")
  end)

  it("win_at inserts right below the window whose slot contains y", function()
    local f = fake_frame()
    f:add_win({ y = 10, h = 40 })
    f:add_win({ y = 50, h = 40 })
    f:add_win({ y = 90, h = 40 })
    eq(f:win_at(5), 1, "above the first window")
    eq(f:win_at(20), 2, "inside window 1 -> after it")
    eq(f:win_at(49), 2, "end of window 1 -> after it")
    eq(f:win_at(60), 3, "inside window 2 -> after it")
    eq(f:win_at(100), 4, "inside window 3 -> to the end")
  end)

  it("win_at returns 1 when not stacked", function()
    local f = frame:new({})
    f:add_win({ y = 10, h = 40 })
    eq(f:win_at(999), 1)
  end)

  it("add does not leave gaps when the position is past the end", function()
    local f = fake_frame()
    f:add_win({ y = 0, h = 10 })
    f:add_win({ y = 0, h = 10 }, 5)
    eq(#f.childs, 3, "menu and two windows")
    for i = 1, #f.childs do
      ok(f.childs[i] ~= nil, "no gap at " .. i)
    end
  end)

  it("normalize toggles the first window layout", function()
    local f = fake_frame()
    local w1, w2, w3 = { frac = 0.5 }, { frac = 0.3 }, { frac = 0.2 }
    f:add_win(w1)
    f:add_win(w2)
    f:add_win(w3)
    f:normalize()
    eq(w1.frac, 1)
    eq(w2.frac, 0)
    eq(w3.frac, 0)
    f:normalize()
    eq(w1.frac, 0.5)
    eq(w2.frac, 0.3)
    eq(w3.frac, 0.2)
  end)

  it("frac_norm distributes evenly when unset", function()
    local f = fake_frame()
    local ws = { {}, {}, {} }
    for _, w in ipairs(ws) do f:add_win(w) end
    f:frac_norm()
    for _, w in ipairs(ws) do
      ok(math.abs(w.frac - 1 / 3) < 1e-9, "frac " .. tostring(w.frac))
    end
  end)

  it("frac_norm keeps zero as a valid fraction", function()
    local f = fake_frame()
    local w1, w2, w3 = { frac = 0.5 }, { frac = 0.5 }, { frac = 0 }
    f:add_win(w1)
    f:add_win(w2)
    f:add_win(w3)
    f:frac_norm()
    eq(w3.frac, 0)
    eq(w1.frac, 0.5)
    eq(w2.frac, 0.5)
  end)

  it("frac_norm fills missing fractions and normalizes", function()
    local f = fake_frame()
    local w1, w2, w3 = { frac = 1 }, { frac = 1 }, {}
    f:add_win(w1)
    f:add_win(w2)
    f:add_win(w3)
    f:frac_norm()
    local sum = w1.frac + w2.frac + w3.frac
    ok(math.abs(sum - 1) < 1e-9, "sum " .. sum)
  end)

  it("stacked_sizes distributes body heights and keeps the remainder", function()
    local f = fake_frame()
    local function mk()
      return { frac = 1 / 3, menu_w = {
        cols = 1,
        geom = function() end,
        realheight = function() return 10 end,
      } }
    end
    f:add_win(mk())
    f:add_win(mk())
    f:add_win(mk())
    local flex, sizes = f:stacked_sizes(100)
    eq(flex, 70, "flexible height")
    eq(sizes[1], 23)
    eq(sizes[2], 23)
    eq(sizes[3], 24, "last window takes the remainder")
  end)

  it("resize_win moves the boundary between two windows", function()
    local f = fake_frame()
    f.flexible = 100
    local w1, w2 = { frac = 0.5 }, { frac = 0.5 }
    f:add_win(w1)
    f:add_win(w2)
    f:resize_win(w2, 20)
    ok(math.abs(w1.frac - 0.7) < 1e-9, "w1 " .. w1.frac)
    ok(math.abs(w2.frac - 0.3) < 1e-9, "w2 " .. w2.frac)
  end)

  it("resize_win collapses a window down to zero", function()
    local f = fake_frame()
    f.flexible = 100
    local w1, w2 = { frac = 0.5 }, { frac = 0.5 }
    f:add_win(w1)
    f:add_win(w2)
    f:resize_win(w2, -999)
    eq(w1.frac, 0)
    ok(math.abs(w2.frac - 1) < 1e-9, "w2 " .. w2.frac)
  end)

  it("resize_win ignores the first window", function()
    local f = fake_frame()
    f.flexible = 100
    local w1, w2 = { frac = 0.5 }, { frac = 0.5 }
    f:add_win(w1)
    f:add_win(w2)
    f:resize_win(w1, 50)
    eq(w1.frac, 0.5)
    eq(w2.frac, 0.5)
  end)
end)

-- frame with a real menu and a frame:file stand-in for the app one
local function dump_frame()
  local f = frame:new(menu:new())
  f.file = function(self, fname, pos)
    local w = win:new(fname)
    self:add_win(w, pos)
    return w
  end
  return f
end

describe("frame dump", function()
  it("restore makes the windows and dump round-trips them", function()
    local f = dump_frame()
    local d = {
      menu = "| New",
      stacked = true,
      frac = 0.5,
      stacked_cmdline = "| cmd",
      { type = "win", fname = "a.txt", text = "hi\n",
        menu = "a | x", frac = 0.6 },
      { type = "shell", fname = "+win", text = "$ ls\n", hist = { "ls" } },
    }
    f:restore(d)
    local wins = {}
    for w in f:for_win() do table.insert(wins, w) end
    eq(#wins, 2)
    eq(wins[1].buf.fname, "a.txt")
    eq(wins[1]:gettext(), "hi\n")
    eq(wins[1].menu, "a | x")
    eq(wins[1].frac, 0.6)
    ok(wins[2].shell, "shell window")
    eq(wins[2].shell.hist[1], "ls")
    eq(wins[2]:gettext(), "$ ls\n")
    eq(f:menu():gettext(), "| New")
    eq(f.stacked, true)
    eq(f.frac, 0.5)
    eq(f.stacked_cmdline, "| cmd")

    local d2 = f:dump()
    eq(d2.menu, "| New")
    eq(d2.stacked, true)
    eq(d2.frac, 0.5)
    eq(d2.stacked_cmdline, "| cmd")
    eq(d2[1].type, "win")
    eq(d2[1].fname, "a.txt")
    eq(d2[1].text, "hi\n")
    eq(d2[2].type, "shell")
    eq(d2[2].hist[1], "ls")
  end)

  it("an unknown kind restores as a plain window", function()
    local f = dump_frame()
    f:restore { { type = "future", fname = "a.txt", text = "hi\n" } }
    local wins = {}
    for w in f:for_win() do table.insert(wins, w) end
    eq(#wins, 1)
    eq(wins[1]:gettext(), "hi\n")
    eq(wins[1].shell, nil)
  end)
end)
