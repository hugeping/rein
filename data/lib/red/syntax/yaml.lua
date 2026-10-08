-- YAML, on the basis of mc's yaml.syntax: the comments, the mapping
-- keys, the document and list markers, the inline substitutions
-- "{{...}}", the quoted strings and the block scalars "|" and ">"
-- (the source ends a block scalar at an empty line followed by a key;
-- here the first line not indented deeper than the key owning the
-- scalar ends it).
local scheme = require "red/scheme"

-- an inline substitution {{ ... }} (Jinja2, Ansible), on one line
local function template(ctx, txt, i)
  if txt[i] ~= '{' or txt[i + 1] ~= '{' then
    return
  end
  local j = i + 2
  while txt[j] and txt[j] ~= '\n' do
    if txt[j] == '}' and txt[j + 1] == '}' then
      return j - i + 2
    end
    j = j + 1
  end
end

-- the "key:" of a mapping: the source restricts the names to word
-- characters, spaces and dashes
local function key(ctx, txt, i)
  if not txt[i] or not txt[i]:find('[%w_]') then
    return
  end
  local j = scheme.rule.skip(txt, i + 1, 1, '[%w_ %-]')
  if txt[j] == ':' then
    local c = txt[j + 1]
    if not c then
      return j - i + 1
    elseif c == ' ' or c == '\n' then
      return j - i + 2
    end
  end
end

-- "---" in the first column, "- " at the line start
local function marker(ctx, txt, i)
  if txt[i] ~= '-' then
    return
  end
  if txt[i + 1] == '-' and txt[i + 2] == '-' and
    scheme.rule.bol(txt, i) then
    return 3
  end
  if txt[i + 1] == ' ' and scheme.rule.bol(txt, i, '[ \t]') then
    return 2
  end
end

-- the column of the key owning the block scalar: the indicator line
-- is scanned back to its colon; a bare "- |" owns from the dash
local function owner(txt, i)
  local bol = scheme.rule.linebegin(txt, i)
  local colon = scheme.rule.rfind(txt, i - 1, bol, ':')
  if not colon then
    return scheme.rule.indent(txt, i)
  end
  local j = scheme.rule.skipspace(txt, colon - 1, -1)
  j = scheme.rule.skip(txt, j, -1, '[^ \t\n]')
  return j + 1 - bol
end

-- a block scalar "|" or ">" with the optional indentation and
-- chomping indicators, up to the end of its line
local function scalar(ctx, txt, i)
  local c = txt[i]
  if c ~= '|' and c ~= '>' then
    return
  end
  local j = scheme.rule.skip(txt, i + 1, 1, '[ \t%+%d%-]')
  if txt[j] == '\n' then
    return j - i, owner(txt, i)
  end
end

-- the end of a block scalar: the first non-empty line not indented
-- deeper than the key owning it
local function endscalar(ctx, txt, i, indent)
  if txt[i] ~= '\n' then
    return
  end
  local j = scheme.rule.skipspace(txt, i + 1, 1)
  if txt[j] and txt[j] ~= '\n' and j - i - 1 <= indent then
    return 1
  end
end

-- the quoted strings, with the substitutions inside
local dquote = scheme.rule.string '"'
table.insert(dquote.keywords, { template, col = scheme.number })
local squote = scheme.rule.string "'"
table.insert(squote.keywords, { template, col = scheme.number })

local col = {
  col = scheme.default,
  keywords = {
    { template, col = scheme.number },
    { "true", "false", "null", col = scheme.keyword, word = true },
    { marker, col = scheme.operator },
    { ", ", ",\n", col = scheme.operator },
    { ",", col = { 255, 0, 0 } },
    { key, col = scheme.lib },
    { "[", "]", "{", "}", col = scheme.operator },
  },
  dquote,
  squote,
  { -- a block scalar
    start = scalar,
    stop = endscalar,
    scol = scheme.operator,
    col = scheme.string,
  },
  scheme.rule.line_comment '#',
}

return col
