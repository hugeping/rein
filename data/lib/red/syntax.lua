local syntax = {}
syntax.__index = syntax

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
  if not ctx[fn] then return end
  if type(ctx[fn]) == 'string' then
    ctx[fn] = utf.chars(ctx[fn])
  end
  if type(ctx[fn]) == 'function' then
    return ctx[fn](ctx, txt, i, ...)
  end
  if startswith(txt, i, ctx[fn]) then
    return #ctx[fn]
  end
end

function syntax:match_start(ctx, txt, i)
  local r = self:match_fn(ctx, txt, i, 'linestart')
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
  return self:match_fn(ctx, txt, i, 'start')
end

function syntax:match_end(ctx, txt, i)
  return self:match_fn(ctx, txt, i, 'stop',
    self.stack[1] and self.stack[1][2])
end

function syntax:context(pos)
  local ctx = self.ctx
  local txt = self.txt
  local cols = self.cols
  local found_len, found_col
  for _, v in ipairs(ctx.keywords or {}) do
    for i, word in ipairs(v) do
      if type(word) == 'string' then
        word = utf.chars(word)
        v[i] = word
      end
      if type(word) == 'function' then
        local r = word(ctx, txt, pos)
        if r and (not found_len or found_len < r) then
          found_len = r
          found_col = v.col or ctx.col
        end
      elseif checkword(v, txt, pos, word) then
        if not found_len or found_len < #word then
          found_len = #word
          found_col = v.col or ctx.col
        end
      end
    end
  end
  if found_len then
    colorize(cols, pos, found_len, found_col)
    return found_len
  end

  local d = self:match_end(ctx, txt, pos)
  if d then
    colorize(cols, pos, d, ctx.col)
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

function syntax:process(pos)
  if not self.ctx then
    return
  end
  local stack = self.stack
  local txt = self.txt
  local cols = self.cols
  local i = self.pos
  if pos < i then -- nothing to do
    return
  end
  while i <= #txt do
    local r, d, aux
    for _, c in ipairs(self.ctx) do
      d, aux = self:match_start(c, txt, i)
      if d then
        colorize(cols, i, d, c.col)
        i = i + d
        table.insert(stack, 1, { self.ctx, aux })
        self.ctx = c
        break
      end
    end
    i = i + self:context(i)
    self.pos = i
    break
  end
end

return syntax
