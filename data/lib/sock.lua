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
    coroutine.yield()
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
  local i = 1
  local len = self.data:len()
  local ret
  ret = self.sock:recv(1024)
  if not ret then
    return false, "Error receiving"
  end
  if ret then
    self.data = self.data .. ret
  end
  return self.data:len()
end

function tcp:recv(len)
  if not self.sock then
    return false
  end
  return self.sock:recv(len)
end

function tcp:send(...)
  if not self.sock then
    return false
  end
  return self.sock:send(...)
end

function tcp:lines(wait)
  while wait and not self.data:find("\n") do
    self:poll()
    coroutine.yield()
  end
  local str = self.data
  local s = str:gsub("^(.*\n)[^\n]*$", "%1")
  self.data = str:sub(s:len()+1) or ''
  return string.lines(s)
end

return sock
