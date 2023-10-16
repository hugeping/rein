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

local col = {
  col = 0,
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
      col = scheme.keyword, word = true
    },
    {
      preproc,
      col = scheme.lib,
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
