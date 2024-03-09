require "std"
local DELAY = 1/30
local sock = {}
sock.__index = sock

local tcp = {}
tcp.__index = tcp

function sock.dial(addr, port)
  local s = { data = '' }
  s.sock = net.dial(addr, port)
  setmetatable(s, tcp)
  return s
end

function tcp:write(data)
  if not self.sock then
    return false
  end
  local i = 1
  local len = data:len()
  local rc, e
  while len > 0 do
    rc, e = self.sock:send(data, i, len)
    if not rc then
      return false, e
    end
    len = len - rc
    i = i + rc
    if not THREAD then
      coroutine.yield()
    else
      sys.sleep(DELAY)
    end
  end
  return true
end

function tcp:close()
  if self.sock then
    self.sock:close()
    self.sock = false
  end
end

function tcp:poll()
  if not self.sock then
    return false
  end
  local ret, e = self.sock:recv(1024)
  if not ret then
    return false, e
  end
  self.data = self.data .. ret
  return self.data:len()
end

function tcp:wait(fn)
  while not fn(self.data) do
    local r, e = self:poll()
    if not r then
      return r, e
    end
    if sys.incoroutine then
      coroutine.yield()
    else
      sys.sleep(DELAY)
    end
  end
end

function tcp:recv(len, wait)
  if not self.sock then
    return false
  end

  if wait then
    local r, e = self:wait(function(s) return s:len() >= len end)
    if not r then
      if self.data ~= '' then
        r, self.data = self.data, ''
        return r
      end
      return r, e
    end
  end

  local dlen = self.data:len()
  local rlen = math.min(len, dlen)
  if rlen > 0 then
    local d = self.data:sub(1, rlen)
    self.data = self.data:sub(rlen + 1)
    local dd = self.sock:recv(len - rlen)
    return d .. (dd or '')
  end
  return self.sock:recv(len)
end

function tcp:println(fmt, a, ...)
  if a ~= nil then
    fmt = string.format(fmt, a, ...)
  end
  return self.sock:send((fmt or '')..'\r\n')
end

function tcp:send(...)
  if not self.sock then
    return false
  end
  return self.sock:send(...)
end

function tcp:readln(wait)
  if wait then
    local r, e = self:wait(function(s) return s:find "\n" end)
    if not r then
      if self.data ~= '' then
        r, self.data = self.data, ''
        return r
      end
      return r, e
    end
  end
  if not self.data:find("\n") then return nil end
  local str = self.data
  local s = str:find("\n", 1, true)
  self.data = str:sub(s + 1)
  if str:sub(s-1, s-1) == '\r' then
    s = s - 1
  end
  return str:sub(1, s-1)
end

function tcp:lines(wait)
  return function()
    return self:readln(wait)
  end
end

return sock
