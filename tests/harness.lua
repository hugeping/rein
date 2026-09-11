-- Minimal zero-dependency test harness (works under LuaJIT).
-- Provides globals: describe, it, eq, ne, ok, match, fail.

local harness = { passed = 0, failed = 0, errors = {} }

local function loc(level)
  local info = debug.getinfo(level + 1, "Sl")
  if not info then return "?" end
  return (info.short_src or "?") .. ":" .. (info.currentline or "?")
end

local function fail(msg, level)
  error(msg, level + 1)
end

function _G.describe(name, fn)
  io.write("# " .. name .. "\n")
  local ok, err = pcall(fn)
  if not ok then
    harness.failed = harness.failed + 1
    harness.errors[#harness.errors + 1] = { name = name, err = err }
    io.write("  ! describe error: " .. tostring(err) .. "\n")
  end
end

function _G.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    harness.passed = harness.passed + 1
    io.write("  ok   " .. name .. "\n")
  else
    harness.failed = harness.failed + 1
    harness.errors[#harness.errors + 1] = { name = name, err = err }
    io.write("  FAIL " .. name .. "\n")
    io.write("       " .. tostring(err) .. "\n")
  end
end

function _G.eq(a, b, msg)
  if a ~= b then
    fail((msg and (msg .. ": ") or "")
      .. "expected " .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end

function _G.ne(a, b, msg)
  if a == b then
    fail((msg and (msg .. ": ") or "") .. "expected values to differ", 2)
  end
end

function _G.ok(cond, msg)
  if not cond then fail(msg or "condition is falsy", 2) end
end

function _G.match(s, pat, msg)
  if type(s) ~= "string" or not s:find(pat) then
    fail((msg and (msg .. ": ") or "")
      .. tostring(s) .. " does not match " .. tostring(pat), 2)
  end
end

function _G.fail(msg)
  fail(msg or "explicit failure", 2)
end

function harness.summary()
  io.write(string.format("\n%d passed, %d failed\n",
    harness.passed, harness.failed))
  return harness.failed == 0 and 0 or 1
end

return harness
