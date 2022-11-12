-- idea taken from the torch7 project
local dumper = {
  UPVALS = false
}

local dump = {
  UPVALS = false
}

local loadstring = loadstring or load

dump.__index = dump

function dump:lines(text)
  text = text:gsub("\r", "")
  local state = {text, 1, 1}
  local function next_line()
    local text, begin, line_n = state[1], state[2], state[3]
    if begin < 0 then
      return nil
    end
    state[3] = line_n + 1
    local b, e = text:find("\n", begin, true)
    if b then
      state[2] = e+1
      return text:sub(begin, e-1), line_n
    else
      state[2] = -1
      return text:sub(begin), line_n
    end
  end
  return next_line
end

function dumper.new(ob)
  local data = {
    objs = { id = 1; };
    refs = { };
    uprefs = { };
    upvals = { };
  }
  setmetatable(data, dump)
  if type(ob) == 'string' then
    return data:load(ob)
  end
  local r, e = data:save(ob)
  if not r then
    return r, e
  end
  return data.dump
end

function dump:objtype(ob)
  local t = type(ob)
  if not ob and type(ob) ~= 'boolean' then
    return 'nil'
  end
  if t == 'function' and pcall(string.dump, ob) then
    return 'function'
  end
  local supported = {
    ['nil'] = true;
    ['table'] = true;
    ['number'] = true;
    ['string'] = true;
    ['boolean'] = true;
  }
  return supported[t] and t
end

function dump:write(msg)
  if type(msg) == 'string' then
    msg = self:esc(msg)
  end
--  print(msg)
  if not self.dump then
    self.dump = ''
  end
  self.dump = self.dump .. msg .. '\n'
end

function dump:pointer(ob)
  return ob
end

function dump:esc(msg)
  local e = ''
  msg = msg:gsub("\\", "\\\\")
  local last = 1
  for i=1,msg:len() do
    local c = string.byte(msg, i)
    if c == 0 then
      e = e .. msg:sub(last, i - 1).. '\\0'
      last = i + 1
    end
  end
  e = e .. msg:sub(last)
  msg = e
  msg = msg:gsub("[\n\r\t]", { ["\t"] = "\\t",
    ["\r"] = "\\r", ["\n"] = "\\n"  })
  return msg
end

function dump:unesc(l)
  l = l:gsub("\\?[\\n\\r\\t\\0]", { ['\\r'] = '\r', ['\\t'] = '\t',
    ['\\n'] = '\n', ['\\0'] = '\x00', ['\\\\'] = '\\' })
  return l
end

function dump:load(iter)
  if type(iter) == 'string' then
    iter = dump:lines(iter)
  end
  local l = iter()
  if l == 'nil' then
    return nil
  elseif l == 'number' then
    l = iter()
    return tonumber(l)
  elseif l == 'boolean' then
    l = iter()
    return l == 'true' and true or false
  elseif l == 'string' then
    l = iter()
    l = self:unesc(l)
    return l
  elseif l == 'table' then
    l = iter()
    local id = tonumber(l)
    local ob = self.refs[id]
    if ob then
      return ob
    end
    ob = {}
    self.refs[id] = ob
    l = iter()
    local nr = tonumber(l)
    for _=1, nr do
      local k = self:load(iter)
      local v = self:load(iter)
      ob[k] = v
    end
    return ob
  elseif l == 'function' then
    l = iter()
    local id = tonumber(l)
    local ob = self.refs[id]
    if ob then
      return ob
    end
    l = iter()
    local f, e = loadstring(self:unesc(l))
    if not f then
      return f, e
    end
    if not self.UPVALS then
      return f
    end
    local upvals = self:load(iter)
    for i, up in ipairs(upvals) do
      if up.nam == '_ENV' then
        debug.setupvalue(f, i, _ENV)
      else
        debug.setupvalue(f, i, up.val)
        if debug.upvaluejoin and up.id then
          if self.uprefs[up.id] then
            local o = self.uprefs[up.id]
            debug.upvaluejoin(f, i, o.fn, o.id)
          else
            self.uprefs[up.id] = { fn = f, id = i }
          end
        end
      end
    end
    return f
  else
    return false, "Wrong format"
  end
end

function dump:save(ob)
  if not ob and type(ob) ~= 'boolean' then
    self:write("nil")
    return true
  end
  local t = self:objtype(ob)
  if not t then
    return false, "Not supported"
  end
  self:write(t)
  if t == 'table' or t == 'function' then
    local id = self.objs[self:pointer(ob)]
    if id then
      self:write(id)
      return true
    end
    self.objs[self:pointer(ob)] = self.objs.id
    self:write(self.objs.id)
    self.objs.id = self.objs.id + 1
  else
    self:write(tostring(ob))
  end
  if t == 'table' then
    local len = 0
    for _ in pairs(ob) do
      len = len + 1
    end
    self:write(len)
    for k,v in pairs(ob) do
      self:save(k)
      self:save(v)
    end
  elseif t == 'function' then
    self:dump_fn(ob)
    if self.UPVALS then
      self:dump_upvalues(ob)
    else
      local idx = 1
      while true do
        local n, _ = debug.getupvalue(ob, idx)
        if not n then break end
        if n ~= '_ENV' then
          return false, "Function with upvalues: "..tostring(n)
        end
        idx = idx + 1
      end
    end
  end
  return true
end

function dump:dump_upvalues(fn)
  local upvals = {}
  local cnt = 0
  local ids = self.upvals
  local upid = 1
  for _ in pairs(ids) do upid = upid + 1 end
  while true do
    cnt = cnt + 1
    local n, v = debug.getupvalue(fn, cnt)
    if not n then break end
    if n == '_ENV' then v = nil end
    local id
    if debug.upvalueid then -- newer lua?
      id = debug.upvalueid(fn, cnt)
      if not ids[id] then
        ids[id] = upid
        upid = upid + 1
      end
      id = ids[id]
    end
    table.insert(upvals, {nam = n, val = v, id = id})
  end
  self:save(upvals)
end

function dump:dump_fn(fn)
  local dumped = string.dump(fn)
  self:write(dumped)
end

function dumper.save(fname, t)
  local f
  local r, e = dumper.new(t)
  if not r then error(e, 2) end
  f, e = io.open(fname, "wb")
  if not f then return false, e end
  f:write(r)
  f:flush()
  f:close()
  return true
end

function dumper.load(fname)
  local r
  local f, e = io.open(fname, "rb")
  if not f then return false, e end
  r, e = f:read("*all")
  if not r then f:close() return false, e end
  r, e = dumper.new(r)
  if not r and e then return false, e end
  return r
end

return dumper
