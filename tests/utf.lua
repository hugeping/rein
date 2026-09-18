-- Lua implementation of rein's `utf` module (src/utf.c) for headless tests.
-- Mirrors: next, prev, len, sym, chars, codepoint, from_codepoint.

local utf = {}

local UTF_MAX = 4

local function utf_ff(s, i)
  local b = s:byte(i)
  if not b then return 0 end
  if b < 0x80 then return 1 end
  local l = 1
  local j = i + 1
  while j <= #s and l < UTF_MAX do
    local c = s:byte(j)
    if not c or c < 0x80 or c >= 0xC0 then break end
    l = l + 1
    j = j + 1
  end
  return l
end

local function utf_bb(s, i)
  local c = s:byte(i)
  if not c then return 0 end
  if c < 0x80 then return 1 end
  local l = 1
  local j = i
  while j > 1 and l < UTF_MAX do
    local p = s:byte(j)
    if not p or p < 0x80 or p >= 0xC0 then break end
    l = l + 1
    j = j - 1
  end
  return l
end

function utf.next(s, pos)
  if not s then return 0 end
  pos = pos or 1
  if pos < 1 or pos > #s then return 0 end
  return utf_ff(s, pos)
end

function utf.prev(s, pos)
  if not s then return 0 end
  pos = pos or 0
  if pos < 0 then pos = #s + pos end
  if pos < 1 or pos > #s then return 0 end
  return utf_bb(s, pos)
end

function utf.len(s)
  local n = 0
  local i = 1
  while i <= #s do
    local l = utf_ff(s, i)
    if l == 0 then break end
    i = i + l
    n = n + 1
  end
  return n
end

function utf.sym(s, pos)
  pos = pos or 1
  if not s or pos < 1 or pos > #s then return end
  local l = utf_ff(s, pos)
  if l == 0 then return end
  return s:sub(pos, pos + l - 1), l
end

function utf.chars(s)
  local t = {}
  local i = 1
  while i <= #s do
    local l = utf_ff(s, i)
    if l == 0 then break end
    t[#t + 1] = s:sub(i, i + l - 1)
    i = i + l
  end
  return t
end

function utf.codepoint(s, pos)
  pos = pos or 1
  if not s or pos < 1 or pos > #s then return 0, 0 end
  local b = s:byte(pos)
  local cp, n
  if b < 0x80 then
    cp, n = b, 0
  elseif b >= 0xF0 then
    cp, n = b % 0x08, 3
  elseif b >= 0xE0 then
    cp, n = b % 0x10, 2
  elseif b >= 0xC0 then
    cp, n = b % 0x20, 1
  else
    cp, n = b, 0
  end
  local i = pos
  while n > 0 do
    i = i + 1
    local c = s:byte(i) or 0
    cp = cp * 64 + c % 64
    n = n - 1
  end
  return cp, i - pos + 1
end

local function div(n, d) return math.floor(n / d) end

function utf.from_codepoint(cp)
  if cp <= 0x7F then
    return string.char(cp)
  elseif cp <= 0x07FF then
    return string.char(0xC0 + div(cp, 64) % 32,
      0x80 + cp % 64)
  elseif cp <= 0xFFFF then
    return string.char(0xE0 + div(cp, 4096) % 16,
      0x80 + div(cp, 64) % 64,
      0x80 + cp % 64)
  else
    return string.char(0xF0 + div(cp, 262144) % 8,
      0x80 + div(cp, 4096) % 64,
      0x80 + div(cp, 64) % 64,
      0x80 + cp % 64)
  end
end

return utf
