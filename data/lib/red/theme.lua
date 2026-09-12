-- Color themes. Colors are copied into the existing conf/scheme
-- tables instead of replacing them: windows, menus and colorizers
-- keep references to those tables and must see the new colors.
local conf = require "red/conf"
local scheme = require "red/syntax/scheme"

local themes = {
  default = require "red/themes/default",
  dark = require "red/themes/dark",
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
