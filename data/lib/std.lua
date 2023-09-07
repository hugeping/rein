math.round = function(num, n)
  local m = 10 ^ (n or 0)
  return math.floor(num * m + 0.5) / m
end

if not table.unpack then
  table.unpack = unpack
end

function table.clone(src)
  local dst = {}
  if type(src) ~= 'table' then return src end
  for k, _ in pairs(src) do
    dst[table.clone(k)] = table.clone(src[k])
  end
  return dst
end

function table.append(dst, ...)
  for _, t in ipairs({...}) do
    table.insert(dst, t)
  end
  return dst
end

function table.push(t, v)
  table.insert(t, v)
  return v
end

function table.pop(t)
  if table.empty(t) then return end
  return table.remove(t, #t)
end

function table.find(t, a)
  for i = 1, #t do
    if t[i] == a then return i end
  end
  return false
end

function table.del(t, a)
  local i = table.find(t, a)
  if i then return table.remove(t, i) end
end

function table.strict(g)
  setmetatable(g, {
    __index = function(_, n)
      local f = debug.getinfo(2, "S").source
      std.err("Uninitialized global variable: %s in %s", n, f)
      std.err(debug.traceback())
    end;
    __newindex = function(t, k, v)
      if type(v) ~= 'function' then
        local f = debug.getinfo(2, "S").source
        if f ~= '=[C]' then
          std.err ("Set uninitialized variable: %s in %s", k, f)
          std.err(debug.traceback())
        end
      end
      rawset(t, k, v)
   end})
end

function string.findln(str, pat)
  local off = 0
  for l in str:lines(true) do
    local ll = l:gsub("\n$", "")
    local s, e = ll:find(pat)
    if s then return off + s, off + e end
    off = off + l:len()
  end
end

function string.empty(str)
  local r = str:find("^[ \t]*$")
  return not not r
end

function string.strip(str, pat)
  if not str then return str end
  pat = pat or " \t\n\r"
  str = str:gsub("^["..pat.."]+",""):gsub("["..pat .. "]+$","")
  return str
end

function string.stripnl(str)
  if not str then return str end
  return string.strip(str, "\n\r")
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

function string.lines(text, eol)
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
      return text:sub(begin, eol and e or e-1), line_n
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
