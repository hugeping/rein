-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function cat(w, f)
  if not f then return end
  w = w:data()
  if not w then return end
  local d = io.file(w:path(f))
  if not d then return end
  local s = w:cur()
  w.buf:input(d)
  w:setsel(s, w:cur() + 1)
  return true
end

return {
  cat = cat,
}
