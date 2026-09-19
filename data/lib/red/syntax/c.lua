local scheme = require "red/scheme"

local function preproc(ctx, txt, pos)
  local i = pos
  if txt[i] ~= '#' then return false end
  if not scheme.rule.bol(txt, i, '[ \t]') then return false end
  while txt[i] and (txt[i] ~= '\n' or txt[i-1]=='\\') do
    i = i + 1
  end
  return i - pos
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
      scheme.rule.number,
      col = scheme.number,
    }
  },
  scheme.rule.block_comment('/*', '*/'),
  scheme.rule.line_comment '//',
  scheme.rule.string '"',
  scheme.rule.string "'",
}

return col
