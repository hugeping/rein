math.round = function(num, n)
  local m = 10 ^ (n or 0)
  return math.floor(num * m + 0.5) / m
end

if not table.unpack then
  table.unpack = unpack
end

function string.empty(str)
  local r = str:find("^[ \t]*$")
  return not not r
end

function string.strip(str)
  if not str then return str end
  str = str:gsub("^[ \t\n\r]+",""):gsub("[ \t\n\r]+$","")
  return str
end

function string.stripnl(str)
  if not str then return str end
  str = str:gsub("^[\n\r]+",""):gsub("[\r\n]+$","")
  return str
end

function string.split(self, n, sep, rexp)
  if type(n) ~= 'number' then
    sep, rexp, n = n, sep, false
  end
  if not sep then
    rexp = true
    sep = "[ \t]+"
  end
  local ret = {}
  if self:len() == 0 then
    return ret
  end
  n = n or -1
  local idx, start = 1, 1
  local s, e = self:find(sep, start, not rexp)
  while s and n ~= 0 do
    ret[idx] = self:sub(start, s - 1)
    idx = idx + 1
    start = e + 1
    s, e = self:find(sep, start, not rexp)
    n = n - 1
  end
  ret[idx] = self:sub(start)
  return ret
end

function string.startswith(s, pfx)
  return s:find(pfx, 1, true) == 1
end

function string.endswith(s, sfx)
  local len = sfx:len()
  if len > s:len() then return false end
  local start = s:len() - len + 1
  return s:find(sfx, start, true) == start
end

function string.lines(text)
  text = text:gsub("\r", "")
  local state = {text, 1, 1}
  local function next_line()
    local text, begin, line_n = state[1], state[2], state[3]
    if text == '' then return nil end
    if begin < 0 then
      return nil
    end
    state[3] = line_n + 1
    local b, e = text:find("\n", begin, true)
    if b then
      state[2] = b == #text and -1 or e+1
      return text:sub(begin, e-1), line_n
    else
      state[2] = -1
      return text:sub(begin), line_n
    end
  end
  return next_line
end

function string.wrap(text, len, delim)
  delim = delim or "[, ]"
  local res = {}
  local s, e = 1, 1
  local last, done
  local us
  while text:len() > 0 do
    s, e = text:find(delim, s)
    if not s then
      us = utf.len(text)
      s = text:len()
      e = s
      done = true
    else
      us = utf.len(text:sub(1, s-1))
    end
    if us >= len then
      last = last or s
      table.insert(res, text:sub(1, last))
      text = text:sub(last + 1)
      last = nil
      s = 1
    else
      last = s
      s = s + 1
    end
    if done then
      table.insert(res, text)
      break
    end
  end
  return res
end

function io.file(fname, data)
  local f, e, d
  if data == nil then
    f, e = io.open(fname, "rb")
    if not f then return f, e end
    d, e = f:read("*all")
    f:close()
    return d, e
  end
  f, e = io.open(fname, "wb")
  if not f then return f, e end
  if data then
    f:write(data)
  end
  f:flush()
  f:close()
  return true
end
