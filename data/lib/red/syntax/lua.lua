local scheme = require "red/syntax/scheme"

local function strblock(txt, i, sym)
  local start = i
  if txt[i] ~= sym then return false end
  i = i + 1
  while txt[i] == '=' do i = i + 1 end
  if txt[i] ~= sym then return false end
  i = i + 1
  return i - start
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
  local n = ''
  if numdelim(txt[i-1]) then
    return false
  end
  while txt[i] and txt[i]:find("[x0-9%.e%+%-]") do
    n = n .. txt[i]
    i = i + 1
  end
  if n:endswith '-' or n:endswith '+' then n = n:gsub('[%+%-]$', '') end
  if tonumber(n) then return n:len() end
  return false
end

local col = {
  col = 0,
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
    { number, col = scheme.number },
  },
  { -- string
    start = '"',
    stop = '"',
    keywords = {
      { '\\"', '\\\\' },
    },
    col = scheme.string,
  },
  { -- string
    start = "'",
    stop = "'",
    keywords = {
      { "\\'", "\\\\" },
    },
    col = scheme.string,
  },
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
  { -- comment
    start = '--',
    stop = '\n',
    col = scheme.comment,
  },
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
