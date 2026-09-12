-- Color themes. Colors are copied into the existing conf/scheme
-- tables instead of replacing them: windows, menus and colorizers
-- keep references to those tables and must see the new colors.
local conf = require "red/conf"
local scheme = require "red/syntax/scheme"

local themes = {
  default = {
    conf = {
      fg = 0,
      bg = 16,
      scroll_bg = 16,
      scroll_fg = 0,
      scroll_brd = 0,
      cursor = 0,
      cursor_over = 8,
      menu = 17,
      menu_brd = { 0x88, 0x88, 0xcc },
      brd = { 0xde, 0xde, 0xde },
      button = { 0x88, 0x88, 0xcc },
      button_brd = 0,
      active = { 0xff, 0x88, 0xcc },
      hl = { 0xee, 0xee, 0x9e },
      break_hl = { 0xff, 0xee, 0xcc },
    },
    scheme = {
      keyword = { 102, 102, 22 },
      comment = { 64, 136, 64 },
      string = { 124, 102, 187 },
      number = { 2, 135, 200 },
      operator = { 0x6d, 0x1d, 0x1d },
      lib = { 184, 92, 97 },
    },
  },
  -- based on the default Helix theme
  dark = {
    conf = {
      fg = { 0xa4, 0xa0, 0xe8 },
      bg = { 0x28, 0x17, 0x33 },--{ 0x3b, 0x22, 0x4c },
      scroll_bg = { 0x28, 0x17, 0x33 },
      scroll_fg = { 0x5a, 0x59, 0x77 },
      scroll_brd = { 0x5a, 0x59, 0x77 },
      cursor = { 0xff, 0xff, 0xff },
      cursor_over = { 0x6f, 0x44, 0xf0 },
      menu = { 0x3b, 0x22, 0x4c }, --{ 0x28, 0x17, 0x33 },
      menu_brd = { 0x5a, 0x59, 0x77 },
      brd = { 0x28, 0x17, 0x33 },
      button = { 0xa4, 0xa0, 0xe8 },
      button_brd = { 0x5a, 0x59, 0x77 },
      active = { 0xdb, 0xbf, 0xef },
      hl = { 0x54, 0x00, 0x99 },
      break_hl = { 0x45, 0x28, 0x59 },
    },
    scheme = {
      keyword = { 0xec, 0xcd, 0xba }, -- almond
      comment = { 0x69, 0x7c, 0x81 }, -- sirocco
      string = { 0xcc, 0xcc, 0xcc }, -- silver
      number = { 0xe8, 0xdc, 0xa0 }, -- chamois
      operator = { 0xdb, 0xbf, 0xef }, -- lilac
      lib = { 0x9f, 0xf2, 0x8f }, -- mint
    },
  },
}

local order = { 'default', 'dark' }

local theme = {
  themes = themes,
  current = 'default',
}

-- never alias conf fields to the theme tables: copy colors in place
-- (references must stay stable) or create a fresh table
local function recolor(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' then
      local d = dst[k]
      if type(d) ~= 'table' then
        d = {}
        dst[k] = d
      end
      for i = 1, 4 do
        d[i] = v[i]
      end
    else
      dst[k] = v
    end
  end
end

function theme.apply(name)
  local t = themes[name]
  if not t then
    return
  end
  recolor(conf, t.conf)
  recolor(scheme, t.scheme)
  theme.current = name
end

function theme.next()
  for i, n in ipairs(order) do
    if n == theme.current then
      return order[i == #order and 1 or i + 1]
    end
  end
  return order[1]
end

return theme
