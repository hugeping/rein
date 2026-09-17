-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local shell = require "red/shell"

local function win_shell(w)
  w = w:output "+win"
  if not w.shell then
    shell.prompt(w)
  end
  shell.win(w)
  return true
end

return {
  win = win_shell,
}
