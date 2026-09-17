-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
--
-- Zerox: a second window on the same buffer, as in acme.  The windows
-- scroll independently, but the text, its undo history, the cursor and
-- the selection belong to the buffer, so they are shared.
local win = require "red/win"

local function zerox(w)
  local data = w:data()

  if not data or not data.frame then
    return true
  end
  local fr = data.frame
  local copy = win:new(data.buf)

  copy.menu = data.menu
  copy.conf = data.conf
  copy.cwd = data.cwd
  copy.pos = data.pos
  copy.isdirty = data.isdirty
  local i = fr:find_win(data)

  fr:add_win(copy, i and i + 1 or nil)
  fr:update(true, true)
  fr:refresh()
  return true
end

return {
  Zerox = zerox,
}
