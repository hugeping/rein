-- Test runner: luajit tests/run.lua tests/*_test.lua
-- or simply: tests/run.sh

local here = (arg[0] or "tests/run.lua"):match("^(.*)/[^/]*$") or "tests"
package.path = here .. "/?.lua;" .. package.path

require "env"
local harness = require "harness"

local files = {}
for i = 1, #arg do
  files[#files + 1] = arg[i]
end
if #files == 0 then
  io.stderr:write("usage: luajit tests/run.lua <test files...>\n")
  os.exit(2)
end

for _, f in ipairs(files) do
  local chunk, err = loadfile(f)
  if not chunk then
    io.write("  ! cannot load " .. f .. ": " .. tostring(err) .. "\n")
    harness.failed = harness.failed + 1
    harness.errors[#harness.errors + 1] = { name = f, err = err }
  else
    local ok, e = pcall(chunk)
    if not ok then
      io.write("  ! error in " .. f .. ": " .. tostring(e) .. "\n")
      harness.failed = harness.failed + 1
      harness.errors[#harness.errors + 1] = { name = f, err = e }
    end
  end
end

os.exit(harness.summary())
