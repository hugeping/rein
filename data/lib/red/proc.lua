local proc = {}

-- proc extensions: every data/lib/red/proc/*.lua returns a table of
-- procedures which is merged into proc (a later file may override an
-- earlier one); dofile loads them into the app env
local dir = DATADIR .. '/lib/red/proc'
local files = sys.readdir(dir) or {}

table.sort(files)
for _, f in ipairs(files) do
  if f:lower():endswith '.lua' then
    local path = dir .. '/' .. f
    local ok, t = pcall(dofile, path)
    if not ok then
      print(string.format("Error loading: %q: %s", path, t))
    elseif type(t) == 'table' then
      table.merge(proc, t)
    end
  end
end

return proc
