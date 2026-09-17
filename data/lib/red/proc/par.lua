-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function par(w)
  w = w:data()
  if not w then return end
  local s, e = w.buf:range()
  local t = {}
  local c
  local i = s
  while i <= e do
    local oi = i
    while i <= #w.buf.text do
      c = w.buf.text[i]
      if c == '\t' or c == ' ' then
        i = i + 1
      else
        break
      end
    end
    if oi ~= i then
      table.append(t, ' ')
    end
    if c ~= '\n' then
      table.append(t, c)
    elseif w.buf.text[i+1] == '\n' then
      table.append(t, '\n', '\n')
    elseif oi == i then
      table.append(t, ' ')
    end
    i = i + 1
  end
  w:input(t)
  w.buf:setsel(s, s + #t)
  return true
end

return {
  par = par,
}
