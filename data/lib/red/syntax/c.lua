local scheme = require "red/syntax/scheme"

local function isspace(a)
  return a == ' ' or a == '\t'
end

local function isstartline(txt, pos)
  local i = pos
  while txt[i] and isspace(txt[i]) do
    i = i - 1
  end
  return not txt[i] or txt[i] == '\n'
end

local function preproc(ctx, txt, pos)
  local i = pos
  if txt[i] ~= '#' then return false end
  if not isstartline(txt, i-1) then return false end
  while txt[i] and (txt[i] ~= '\n' or txt[i-1]=='\\') do
    i = i + 1
  end
  return i - pos
end

local function numdelim(c)
  if not c then return false end
  if c:find("[a-zA-Z0-9]") then return true end
  local num_delim = {
    [')'] = true,
    [']'] = true,
  }
  return num_delim[c]
end

local function number(ctx, txt, i)
  local start = i
  local n = ''
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

local col = {
  col = scheme.default,
  keywords = {
    { "!", "%%", "&&", "&", "(", ")", "*", "+",
      ",", "-", "/", ":", ";", "<", "=", ">", "?", "[",
      "]", "^", "{", "||", "|", "}", "~", col = scheme.operator
    },
    { "auto", "break", "case", "char", "const", "continue", "do",
      "double", "else", "enum", "extern", "float", "for",
      "goto", "if", "int", "long", "register", "return",
      "short", "signed", "sizeof", "static", "struct",
      "switch", "typedef", "union", "unsigned", "void",
      "volatile", "while", "asm", "inline", "wchar_t",
      "default",
      col = scheme.keyword, word = true
    },
    {
      preproc,
      col = scheme.lib,
    },
    {
      number,
      col = scheme.number,
    }
  },
  { -- comments
    start = '/*';
    stop = '*/';
    col = scheme.comment;
  },
  {
    -- comments
    start = '//';
    stop = '\n';
    col = scheme.comment;
  },
  { -- string
    start = '"',
    stop = '"',
    keywords = {
      { '\\"', '\\\\' },
    },
    col = scheme.string,
  },
}

return col
