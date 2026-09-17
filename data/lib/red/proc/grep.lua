-- A proc extension: red/proc.lua loads every file of this directory and
-- merges the returned table into proc.
local grep_bin = { o = true, ko = true, exe = true, a = true }

local function grep_filter(fn)
  if fn == 'red.dump' then return false end
  return not grep_bin[fn:match('%.([^.]+)$')]
end

local function grep(path, rex, err)
  for _, fn in ipairs(sys.readdir(path)) do
    local p = (path ..'/'..fn):gsub("/+", "/")
    if sys.isdir(p) then
      if not fn:startswith '.' then
        grep(p, rex, err)
      end
    elseif grep_filter(fn) then
      local f = io.open(p, "rb")
      if f then
        local nr = 0
        local epath = err:path(p) --err:path(sys.realpath(p))
        for l in f:lines() do
          nr = nr + 1
          if l:find(rex) then
            err:printf("%s:%d %s\n", epath, nr, l)
            err:scroll_output()
          end
          if nr % 1000 == 0 then
            coroutine.yield(true)
          end
        end
        f:close()
      end
      coroutine.yield(true)
    end
  end
end

local function grep_proc(w, rex)
  if not rex then return end
  local data = w:data()
  local path = data and data:path() or sys.dirname(w.frame:getfilename())
  w = w:output '+grep'
  w.cmdline = w.scroll_mode and 'Noscroll' or 'Scroll'
  w.frame:update()
  w:tail()
  w.cwd = nil
  w:run(function() grep(path, rex, w) end)
  return true
end

return {
  grep = grep_proc,
}
