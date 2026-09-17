-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function dump(w, text)
  for i = 1, #text, 16 do
    local a = ''
    local t = string.format("%04x | ", (i - 1)/16)
    for k = 0, 15 do
      local b = string.byte(text, i + k)
      if not b then
        t = t .. string.rep('   ', 16 - k)
        break
      end
      t = t .. string.format("%02x", b) .. ' '
      if b < 32 then
        b = 46
      end
      a = a .. string.char(b)
    end
    w:printf("%s| %s\n",t, a)
  end
end

local function dump_export(w)
  local ret = {}
  for l in w:gettext():lines() do
    local hex = l:match('|(.-)|')
    if not hex then break end
    for v in hex:gmatch('%S+') do
      table.insert(ret, string.char(tonumber('0x'..v) or 32))
    end
  end
  local t = table.concat(ret, '')
  w:clear()
  dump(w, t)
  return t
end

local function dump_save(self)
  if not self.buf:isfile() then
    return
  end
  local r, e = io.file(self.buf.fname, dump_export(self) or '')
  if r then
    self:nodirty()
  else
    self.frame:err(e)
  end
  return r, e
end

local function hex_dump(w)
  local data = w:data()
  if not data then return end
  w = w:output('+dump')
  w.cmd = { Get = dump_export }
  w.save = dump_save
  local s, e = data.buf:range()
  dump(w, data.buf:gettext(s, e))
  w:scroll_output()
  return true
end

return {
  dump = hex_dump,
}
