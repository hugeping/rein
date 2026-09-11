-- Headless environment: stubs for rein globals used by red Lua modules.
-- Run from the repo root (tests/run.sh does that).

local here = (arg[0] or "tests/run.lua"):match("^(.*)/[^/]*$") or "tests"
local root = here .. "/.."

package.path = root .. "/data/lib/?.lua;"
  .. root .. "/data/lib/?/init.lua;"
  .. here .. "/?.lua;"
  .. package.path

utf = require "utf"
require "std"

sys = {
  _clip = nil,
  clipboard = function(v)
    if v ~= nil then sys._clip = v end
    return sys._clip
  end,
  time = function() return os.clock() end,
  event_filter = function() return {} end,
  window_size = function() return 800, 600 end,
}

scr = { spw = 8, sph = 16, w = 800, h = 600 }

screen = setmetatable({
  size = function() return 800, 600 end,
}, {
  __index = function() return function() end end,
})

SCALE = 1
font = {
  size = function() return 8, 16 end,
}
gfx = {
  win = function() end,
  font = function() return {} end,
  border = function() end,
}

input = {
  mouse = function() return 0, 0, {} end,
  keydown = function() return false end,
}

PLATFORM = "Linux"
DATADIR = root .. "/data"

conf = require "red/conf"
require("red/win"):init(conf)
