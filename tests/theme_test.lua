local theme = require "red/theme"
local conf = require "red/conf"
local scheme = require "red/scheme"

local function restore()
  theme.apply "default"
end

describe("theme", function()
  it("provides the default and dark themes", function()
    ok(theme.themes.default, "default theme")
    ok(theme.themes.dark, "dark theme")
  end)

  it("keeps the syntax default color dynamic", function()
    eq(scheme.default, false, "default falls back to conf.fg")
  end)

  it("recolors tables in place", function()
    local kw, brd = scheme.keyword, conf.brd
    local dark = theme.themes.dark.conf
    theme.apply "dark"
    eq(theme.current, "dark")
    eq(conf.bg[1], dark.bg[1], "window background")
    eq(conf.scroll_bg[1], dark.scroll_bg[1], "scrollbar background")
    eq(conf.scroll_fg[1], dark.scroll_fg[1], "scrollbar thumb")
    eq(conf.scroll_brd[1], dark.scroll_brd[1], "scrollbar frame")
    eq(scheme.keyword, kw, "keyword table kept")
    ne(kw[1], 102, "keyword recolored")
    eq(conf.brd, brd, "border table kept")
    ne(brd[1], 0xde, "border recolored")
    eq(brd[1], conf.bg[1], "border matches the window background")
    restore()
  end)

  it("restores the default theme", function()
    theme.apply "dark"
    theme.apply "default"
    eq(theme.current, "default")
    eq(conf.bg, 16, "background index")
    eq(conf.scroll_bg, 16, "scrollbar background index")
    eq(conf.scroll_fg, 0, "scrollbar thumb index")
    eq(conf.scroll_brd, 0, "scrollbar frame index")
    eq(scheme.keyword[1], 102, "keyword color")
    eq(scheme.string[3], 187, "string color")
  end)

  it("recolors syntax highlighting", function()
    local syntax = require "red/syntax"
    theme.apply "dark"
    local chars = utf.chars("local x = 1")
    local s = syntax.new(chars, 1, "lua")
    for i = 1, #chars do
      s:process(i, #chars)
    end
    eq(s.cols[1], scheme.keyword, "keyword color")
    eq(s.cols[7] or conf.fg, conf.fg, "plain text follows conf.fg")
    restore()
  end)

  it("does not corrupt the theme tables on switching", function()
    local dark = theme.themes.dark.conf
    local def = theme.themes.default.conf
    local def_menu = def.menu_brd[1]
    local dark_brd = dark.brd[1]
    local dark_button_brd = dark.button_brd[1]
    local dark_menu_brd = dark.menu_brd[1]
    theme.apply "default"
    theme.apply "dark"
    theme.apply "default"
    theme.apply "dark"
    eq(def.menu_brd[1], def_menu, "default theme menu border intact")
    eq(dark.brd[1], dark_brd, "dark theme border intact")
    eq(dark.button_brd[1], dark_button_brd, "dark theme button border intact")
    eq(dark.menu_brd[1], dark_menu_brd, "dark theme menu border intact")
    restore()
  end)

  it("cycles themes and ignores unknown names", function()
    restore()
    eq(theme.next(), "dark")
    theme.apply "dark"
    eq(theme.next(), "default")
    theme.apply "nope"
    eq(theme.current, "dark", "unknown theme ignored")
    restore()
  end)
end)
