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

local alpha_default = {}
for c in ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"):gmatch('.') do
  alpha_default[c] = true
end

local function isalpha(a, alpha)
  if not a then return end
  if alpha then
    return a:find(alpha)
  end
  return alpha_default[a]
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

local function checkword(v, txt, pos, pfx)
  if not pfx or not startswith(txt, pos, pfx) then
    return false
  end
  if not v.word then
    return true
  end
  if v.word == 'left' then
    return not isalpha(txt[pos-1], v.alpha)
  end
  if v.word == 'right' then
    return not isalpha(txt[pos+#pfx], v.alpha)
  end
  return not isalpha(txt[pos + #pfx], v.alpha) and
    not isalpha(txt[pos - 1], v.alpha)
end

function syntax:state(s)
  local src = s or self
  local stack = {}
  for _, v in ipairs(src.stack) do
    table.insert(stack, { v[1], v[2] })
  end
  if s then
    self.pos, self.stack, self.ctx = s.pos, stack, s.ctx
    return
  end
  return {
    stack = stack,
    pos = self.pos,
    ctx = self.ctx,
  }
end

-- keyword candidates for the current symbol: only the words starting
-- with it (functions are always tried), in the scheme order
local first_cache = {}
local function candidates(ctx, c)
  local cache = first_cache[ctx]
  if not cache then
    cache = {}
    first_cache[ctx] = cache
  end
  local list = cache[c]
  if list then
    return list
  end
  list = {}
  for _, v in ipairs(ctx.keywords) do
    for _, word in ipairs(v) do
      if type(word) == 'function' then
        table.insert(list, { v, false, word })
      else
        if type(word) == 'string' then
          word = chars(word)
        end
        if word[1] == c then
          table.insert(list, { v, word })
        end
      end
    end
  end
  cache[c] = list
  return list
end

-- precomputed start/stop rules of the scheme contexts
local starts_cache = {}
local function starts(ctxs)
  local list = starts_cache[ctxs]
  if list then
    return list
  end
  list = {}
  for _, c in ipairs(ctxs) do
    local e = { c = c }
    local ls = c.linestart
    if type(ls) == 'string' then
      e.ls = chars(ls)
    elseif ls then
      e.ls_fn = ls
    end
    local st = c.start
    if type(st) == 'string' then
      e.pfx = chars(st)
    elseif st then
      e.fn = st
    end
    list[#list + 1] = e
  end
  starts_cache[ctxs] = list
  return list
end

local stop_cache = {}
local function stop_of(ctx)
  local s = stop_cache[ctx]
  if s ~= nil then
    return s or nil
  end
  local st = ctx.stop
  if type(st) == 'string' then
    s = { pfx = chars(st) }
  elseif st then
    s = { fn = st }
  else
    s = false
  end
  stop_cache[ctx] = s
  return s or nil
end

-- only spaces may precede i on its line
local function linestart_ok(txt, i, spaces)
  for pos = i - 1, 1, -1 do
    if txt[pos] == '\n' then
      break
    end
    if not isspace(txt[pos], spaces) then
      return false
    end
  end
  return true
end

function syntax:context(pos)
  local ctx = self.ctx
  local txt = self.txt
  local cols = self.cols
  local found_len, found_col
  if ctx.keywords then
    for _, e in ipairs(candidates(ctx, txt[pos])) do
      local v = e[1]
      if e[2] then
        local word = e[2]
        if checkword(v, txt, pos, word) then
          if not found_len or found_len < #word then
            found_len = #word
            found_col = v.col or ctx.col
          end
        end
      else
        local r = e[3](ctx, txt, pos)
        if r and (not found_len or found_len < r) then
          found_len = r
          found_col = v.col or ctx.col
        end
      end
    end
  end
  if found_len then
    colorize(cols, pos, found_len, found_col)
    return found_len
  end

  local s = stop_of(ctx)
  if s then
    local d
    if s.pfx then
      if startswith(txt, pos, s.pfx) then
        d = #s.pfx
      end
    else
      d = s.fn(ctx, txt, pos, self.stack[1] and self.stack[1][2])
    end
    if d then
      colorize(cols, pos, d, ctx.ecol or ctx.col)
      self.ctx = table.remove(self.stack, 1)[1]
      return d
    end
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
    checkpoints = {}, scheme = scheme,
    ctx = ctx }
  setmetatable(s, syntax)
  s.checkpoints[1] = s:state()
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
  cols[i] = self.ctx.col
  for _, e in ipairs(starts(self.ctx)) do
    local c = e.c
    d, aux = nil, nil
    if e.ls then
      if startswith(txt, i, e.ls) and
        linestart_ok(txt, i, c.spaces) then
        d = #e.ls
      end
    elseif e.ls_fn then
      local r = e.ls_fn(c, txt, i, epos)
      if r and linestart_ok(txt, i, c.spaces) then
        d = r
      end
    end
    if not d then
      if e.pfx then
        if startswith(txt, i, e.pfx) then
          d = #e.pfx
        end
      elseif e.fn then
        d, aux = e.fn(c, txt, i, epos)
      end
    end
    if d then
      colorize(cols, i, d, c.scol or c.col)
      i = i + d
      table.insert(stack, 1, { self.ctx, aux })
      self.ctx = c
      break
    end
  end
  i = i + self:context(i)
  self.pos = i
end

return syntax
