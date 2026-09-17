-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function is_space(c)
  return c == ' ' or c == '\t' or c == '\n'
end

local function fmt(w, width)
  width = tonumber(width) or 60
  w = w:data()
  if not w then return end
  local s, e = w.buf:range()
  local len = 0
  local t = {}
  local last
  for i = s, e do
    local c = w.buf.text[i]
    if c == '\n' and not is_space(w.buf.text[i+1])
      and not is_space(w.buf.text[i-1]) then c = ' ' end
    table.insert(t, c)
    len = len + 1
    if len >= width then
      if not last then
        table.insert(t, '\n')
        len = 0
      else
        len = #t - last
        table.insert(t, last + 1, '\n')
        last = false
      end
    elseif c == '\n' then
      len = 0
      last = false
    elseif c == ' ' or c == '\t' then
      last = #t
    end
  end
  w:text_replace(function() return table.concat(t) end)
  return true
end

return {
  fmt = fmt,
}
