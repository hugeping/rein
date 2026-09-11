-- Static analysis config for the red Lua code.
-- `luacheck data/apps/red.lua data/lib/red/*.lua`
std = "luajit"
max_line_length = false

-- Globals provided by the rein runtime (C) or boot/app code.
globals = {
  "screen", "scr", "sys", "input", "utf", "conf", "PLATFORM",
  "DATADIR", "gfx", "mixer", "thread", "font", "ARGS", "keybind",
  "SCALE",
}

-- Helpers installed at runtime by lib/std.lua and red.lua.
globals.math = { fields = { "round" } }
globals.table = { fields = { "append", "find", "del", "clone", "merge", "unpack" } }
globals.io = { fields = { "file", "access" } }
globals.string = { fields = {
  "split", "strip", "esc", "unesc", "startswith", "endswith",
  "lines", "empty", "escencode", "escdecode", "escsplit",
} }
