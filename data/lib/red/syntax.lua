local syntax = {}
syntax.__index = syntax

-- cache UTF-8 char arrays for scheme strings without mutating the scheme
local chars_cache = {}
local function chars(word)
  local c = chars_cache[word]
  if not c then
    c = utf.chars(word)
    chars_cache[word] = c
  end
  return c
end

local function colorize(col, pos, len, c)
  for i=pos, pos+len-1 do
    col[i] = c
  end
end

local function isalpha(a, alpha)
  if a and a:find(alpha or "[a-zA-Z0-9_]") then
    return true
  end
end

local function isspace(a, spaces)
  if a and a:find(spaces or "[ \t]") then
    return true
  end
end

local function startswith(txt, pos, pfx)
  for i = 1, #pfx do
    if txt[pos+i-1] ~= pfx[i] then
      return false
    end
  end
  return true
end

local function isword(v, txt, pos, pfx)
  if not startswith(txt, pos, pfx) then
    return false
  end
  if isalpha(txt[pos + #pfx], v.alpha) or
    isalpha(txt[pos - 1], v.alpha) then
    return false
  end
  return true
end

local function checkword(v, txt, pos, pfx)
  if not pfx then return false end
  if not v.word then
    return startswith(txt, pos, pfx)
  elseif v.word == 'left' then
    return startswith(txt, pos, pfx) and
      not isalpha(txt[pos-1], v.alpha)
  elseif v.word == 'right' then
    return startswith(txt, pos, pfx) and
      not isalpha(txt[pos+#pfx], v.alpha)
  end
  return isword(v, txt, pos, pfx)
end

function syntax:match_fn(ctx, txt, i, fn, ...)
  local v = ctx[fn]
  if not v then return end
  if type(v) == 'string' then
    v = chars(v)
  end
  if type(v) == 'function' then
    return v(ctx, txt, i, ...)
  end
  if startswith(txt, i, v) then
    return #v
  end
end

function syntax:match_start(ctx, txt, i, epos)
  local r = self:match_fn(ctx, txt, i, 'linestart', epos)
  if r then
    local ok = true
    for pos = i-1, 1, -1 do
      if txt[pos] == '\n' then
        break
      end
      if not isspace(txt[pos], ctx.spaces) then
        ok = false
        break
      end
    end
    if ok then return r end
  end
  return self:match_fn(ctx, txt, i, 'start', epos)
end

function syntax:match_end(ctx, txt, i)
  return self:match_fn(ctx, txt, i, 'stop',
    self.stack[1] and self.stack[1][2])
end

function syntax:state(s)
  if s then
    self.pos = s.pos
    self.stack = s.stack
    self.ctx = s.ctx
    return
  end
  local stack = {}
  for _, v in ipairs(self.stack) do
    table.insert(stack, { v[1], v[2] })
  end
  return {
    stack = stack,
    pos = self.pos,
    ctx = self.ctx,
  }
end

function syntax:context(pos, epos)
  local ctx = self.ctx
  local txt = self.txt
  local cols = self.cols
  local found_len, found_col
  for _, v in ipairs(ctx.keywords or {}) do
    for _, word in ipairs(v) do
      if type(word) == 'function' then
        local r = word(ctx, txt, pos)
        if r and (not found_len or found_len < r) then
          found_len = r
          found_col = v.col or ctx.col
        end
      else
        if type(word) == 'string' then
          word = chars(word)
        end
        if checkword(v, txt, pos, word) then
          if not found_len or found_len < #word then
            found_len = #word
            found_col = v.col or ctx.col
          end
        end
      end
    end
  end
  if found_len then
    colorize(cols, pos, found_len, found_col)
    return found_len
  end

  local d = self:match_end(ctx, txt, pos, epos)
  if d then
    colorize(cols, pos, d, ctx.ecol or ctx.col)
    self.ctx = table.remove(self.stack, 1)[1]
    return d
  end
  cols[pos] = ctx.col
  return 1
end

function syntax.new(txt, pos, scheme)
  local ctx
  if type(scheme) == 'string' then
    ctx = require('red/syntax/'..scheme)
  end
  local s = { stack = {}, txt = txt,
    pos = pos, start = pos, cols = {},
    ctx = ctx }
  setmetatable(s, syntax)
  return s
end

function syntax:process(pos, epos)
  if not self.ctx then
    return
  end
  local stack = self.stack
  local txt = self.txt
  local cols = self.cols
  local i = self.pos
  if i > pos or i > #txt or i > epos then -- nothing to do
    return
  end
  local d, aux
  cols[i] = self.ctx.col or 0
  for _, c in ipairs(self.ctx) do
    d, aux = self:match_start(c, txt, i, epos)
    if d then
      colorize(cols, i, d, c.scol or c.col)
      i = i + d
      table.insert(stack, 1, { self.ctx, aux })
      self.ctx = c
      break
    end
  end
  i = i + self:context(i, epos)
  self.pos = i
end

return syntax
