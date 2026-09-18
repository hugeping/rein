-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function cat(w, f)
  if not f then return end
  w = w:data()
  if not w then return end
  local d = io.file(w:path(f))
  if not d then return end
  -- buf:input replaces the selection (when there is one) and puts the
  -- text at the cursor: select exactly what was inserted
  local s = w:cur()

  if w.buf:issel() then
    s = w.buf:selrange()
  end
  w.buf:input(d)
  w:setsel(s, w.buf.cur)
  return true
end

return {
  cat = cat,
}
