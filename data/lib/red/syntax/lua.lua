local scheme = require "red/scheme"

local function strblock(txt, i, sym)
  local start = i
  if txt[i] ~= sym then return false end
  i = i + 1
  while txt[i] == '=' do i = i + 1 end
  if txt[i] ~= sym then return false end
  i = i + 1
  return i - start
end

local col = {
  col = scheme.default,
  keywords = {
    { "(", ")", "{", "}", "[", "]", ".", ",", ";", ":",
      "..", "...", "==", "~=", "<=", "=>", ">", "<", "+", "-",
      "*", "/", "^", col = scheme.operator },
    { "and", "break", "do", "else", "elseif", "end", "false",
      "for", "function", "if", "in", "local", "nil",
      "not", "or", "repeat", "return", "then", "true",
      "until", "while", col = scheme.keyword, word = true
    },
    { "error", "getmetatable", "setmetatable", "getfenv",
      "setfenv", "next", "ipairs", "pairs", "print", "tunumber",
      "tostring", "type", "assert", "rawequal", "rawget", "rawset",
      "pcall", "xpcall", "collectgarbage", "gcinfo", "loadfile",
      "dofile", "loadstring", "coroutine.create", "coroutine.wrap",
      "coroutine.resume", "coroutine.yield", "coroutine.status",
      col = scheme.lib, word = true
    },
    { scheme.rule.number, col = scheme.number },
  },
  scheme.rule.string '"',
  scheme.rule.string "'",
  { -- comment
    start = function(ctx, txt, i)
      if txt[i] ~= '-' or txt[i+1] ~= '-' then return false end
      i = i + 2
      local r = strblock(txt, i, '[')
      if not r then return r end
      return r + 2, r
    end,
    stop = function(ctx, txt, i, len)
      local r = strblock(txt, i, ']')
      if not r or r ~= len then return false end
      return r
    end,
    col = scheme.comment,
  },
  scheme.rule.line_comment '--',
  { -- string
    start = function(ctx, txt, i)
      local r = strblock(txt, i, '[')
      if not r then return r end
      return r, r
    end,
    stop = function(ctx, txt, i, len)
      local r = strblock(txt, i, ']')
      if not r or r ~= len then return false end
      return r
    end,
    col = scheme.string,
  }
}

return col
