-- The colors of the schemes and the rule helpers they share.  The file
-- lives outside red/syntax/ on purpose: "Syntax <name>" loads only the
-- schemes, the helpers must not be mistaken for one.
local scheme = {
  -- false means "use conf.fg", so themes may recolor the default text
  default = false,
  keyword = { 102, 102, 22 },
  comment = { 64, 136, 64 },
  string = { 124, 102, 187 },
  number = { 2, 135, 200 },
  operator = { 0x6d, 0x1d, 0x1d },
  lib = { 184, 92, 97 },
}

-- the helpers of the scheme rules
scheme.rule = {}

-- the position i starts its line: only the symbols of `spaces` (a Lua
-- pattern, e.g. "[ \t]" for the indentation) may precede it, with no
-- pattern nothing may
function scheme.rule.bol(txt, i, spaces)
  for pos = i - 1, 1, -1 do
    if txt[pos] == '\n' then
      return true
    end
    if not spaces or not txt[pos]:find(spaces) then
      return false
    end
  end
  return true
end

local num_delim = {
  [')'] = true,
  [']'] = true,
}

local function numdelim(c)
  if not c then return false end
  if c:find("[a-zA-Z0-9]") then return true end
  return num_delim[c]
end

-- a number: 0x1F, 1.5e-3, -7 (C, Lua); not after a word character
function scheme.rule.number(ctx, txt, i)
  local n = ''
  local start = i
  if numdelim(txt[i-1]) then
    return false
  end
  if txt[i] == '+' then return false end
  if txt[i] == '-' then i = i + 1 end
  while txt[i] and txt[i]:find("[x0-9%.a-fA-F]") do
    n = n .. txt[i]
    i = i + 1
  end
  if tonumber(n) then return i - start end
  return false
end

-- a run of digits (Go, Python)
function scheme.rule.digits(ctx, txt, i)
  local n = ''
  local start = i
  while txt[i] and txt[i]:find("[0-9]") do
    n = n .. txt[i]
    i = i + 1
  end
  if n ~= '' then return i - start end
  return false
end

-- the escapes of a quoted string: the closing quote and the backslash
local escapes = {
  ['"'] = { '\\"', '\\\\' },
  ["'"] = { "\\'", "\\\\" },
}

-- the rule of a string quoted with q: "..", '..', """.."""
function scheme.rule.string(q)
  local esc = escapes[q:sub(1, 1)]
  return {
    start = q,
    stop = q,
    col = scheme.string,
    keywords = esc and { esc } or nil,
  }
end

-- the rule of a comment from the mark to the end of the line
function scheme.rule.line_comment(mark)
  return { start = mark, stop = '\n', col = scheme.comment }
end

-- the rule of a comment from open to close
function scheme.rule.block_comment(open, close)
  return { start = open, stop = close, col = scheme.comment }
end

return scheme
