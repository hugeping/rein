-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function dos2unix(w)
  w = w:data()
  if not w then return end
  w:text_replace(function(text)
    return (text:gsub("\r", ""))
  end)
  return true
end

return {
  dos2unix = dos2unix,
}
