-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local function get_tab(w)
  if w:getconf 'spaces_tab' then
    return string.rep(" ", w:getconf 'ts')
  end
  return '\t'
end

local function indent(w)
  w = w:data()
  if not w then return end
  local tab = get_tab(w)
  w:text_replace(function(text)
    local t = ''
    for l in text:lines(true) do
      t = t .. tab .. l
    end
    return t
  end)
  return true
end

local function unindent(w)
  w = w:data()
  if not w then return end
  local tab = get_tab(w)
  w:text_replace(function(text)
    local t = ''
    for l in text:lines(true) do
      if l:startswith(tab) then
        l = l:sub(tab:len()+1)
      end
      t = t .. l
    end
    return t
  end)
  return true
end

return {
  ["i+"] = indent,
  ["i-"] = unindent,
}
