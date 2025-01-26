local W, H = screen:size()
local FW, FH = font:size(" ")

local function scan_dir(dir, tag)
  local ret = {}
  for _, n in ipairs(sys.readdir(dir) or {}) do
    if n:find("%.[lL][uU][aA]$") then
      local name = n:gsub("%.[lL][uU][aA]$", "")
      table.insert(ret, { (dir .. '/'.. n):gsub("/+", "/"), name, tag = tag })
    end
  end
  table.sort(ret, function(a, b) return a[1] < b[1] end)
  return ret
end

local apps

local function rescan_dirs()
  apps = {}
  if #ARGS > 1 then
    for i = 2, #ARGS do
      table.append(apps, table.unpack(scan_dir(ARGS[i])))
    end
  else
    apps = scan_dir(DATADIR..'/apps', 'apps')
    table.append(apps, table.unpack(scan_dir('.'))) -- curdir
    table.append(apps, table.unpack(scan_dir('demo', 'demo'))) -- demos3
    table.append(apps, table.unpack(scan_dir('doc/tutorial', 'tutorial'))) -- demos3
  end
end

local start = 1
local select = 1
local D = FH + 2
local NR = math.floor((H - 70)/ D) - 4

local function init()
  rescan_dirs()
  sys.title "REIN"
  gfx.icon(gfx.new(DATADIR..'/icon.png'))
end

local logo = gfx.new
[[0----56---------
--------------------------------
--------------------------------
--------------5005--------------
--------------0550--------------
--------------0550--------------
------505----005500----505------
-----50505-0055555500-50505-----
-----0555005555555555005550-----
-----5055555500000055555505-----
------5055500------0055505------
-------05506--------60550-------
------05506---0000---60550------
------0550--50555505--0550------
-----0550---05555550---0550-----
--5000550--0555555550--0550005--
--0555550--0555555550--0555550--
--0555550--0555555550--0555550--
--5000550--0555555550--0550005--
-----0550---05555550---0550-----
------0550--50555505--0550------
------05506---0000---60550------
-------05506--------60550-------
------5055500------0055505------
-----5055555500000055555505-----
-----0555005555555555005550-----
-----50505-0055555500-50505-----
------505----005500----505------
--------------0550--------------
--------------0550--------------
--------------5005--------------
--------------------------------
--------------------------------]]

local function header()
  logo:blend(screen, 4, 6)
  gfx.printf(40, 4, 1, [[REIN Version:%s
(c)2023-2025 Peter Kosyh
https://hugeping.ru

Peter Sovietov
(Sound system)]], VERSION)
end

local function help()
  gfx.printf(4, 64, 0,
[[Usage:
  rein edit [file] - edit file
  rein sprited     - gfx editor
  rein voiced      - sfx editor
  rein irc         - irc client
  rein [-s] [-fs] <lua file>

Try:
  rein demo/aadv.lua - run&play
Or:
  rein edit demo/aadv.lua
  then press F1 for help

Doc:
  rein edit doc/api-ru.md

Tutorial:
  Look into doc/tutorial/

Chat with community:
  rein irc

        Happy hacking!]])
end

local help_mode
local delete_mode

local function border()
  if delete_mode then
    gfx.border({255, 0, 0 })
    return
  end
  local fl = math.floor(sys.time())%2
  gfx.border(fl == 1 and 7 or 12)
end

init()

while sys.running() do
  while help_mode do
    screen:clear(16)
    header()
    help()
    border()
    if sys.input() == 'keydown' then
      help_mode = false
      break
    end
    coroutine.yield()
  end
  screen:clear(16)
  header()

  if delete_mode then
    gfx.printf(4, H - 2*FH, 1, [[Remove file? Press Y to confirm!]])
  else
    gfx.printf(4, H - 2*FH, 1, [[F1-help ⬇,⬆,z-run,x-edit,del-remove
shift+esc-exit]])
  end

  local xoff, yoff = 26 + 7, 72
  local tag2col = {
    apps = 9;
    demo = 11;
    tutorial = 12;
  }
  for i = start, #apps do
    local nr = i - start + 1
    local name = apps[i][2]
    if i == select then
      gfx.print("➡", xoff, yoff + nr*D,
        math.floor(sys.time()*5)%2 == 1 and 7 or 1)
    end
    local n = apps[i][2]
    if apps[i].tag and apps[i].tag ~= 'apps' then n = apps[i].tag..'/'..n end
    gfx.print(n, xoff + 1*FW, yoff + nr*D, tag2col[apps[i].tag or ''] or 0)
    if nr >= NR then
      break
    end
  end
  gfx.flip(1/20, true)
  local e, v, a, b = sys.input()
  if e == 'keydown' then
    if v == 'up' then
      select = select - 1
    elseif v == 'down' then
      select = select + 1
    elseif v == 'pagedown' or v == 'keypad 3' then
      select = select + NR
    elseif v == 'pageup' or v == 'keypad 9' then
      select = select - NR
    elseif v == 'f1' then
      help_mode = true
    elseif v == 'z' or v == 'return' or v == 'space' then
      local state = sys.prepare()
      sys.reset()
      sys.exec(apps[select][1])
      sys.suspend()
      -- resumed
      init()
      sys.resume(state)
    elseif v == 'x' then
      local alt = input.keydown 'alt'
      local state = sys.prepare()
      sys.reset()
      sys.exec(alt and "red" or "edit",
        apps[select][1])
      sys.suspend()
      -- resumed
      sys.resume(state)
    elseif (v == 'delete' or v == 'backspace') then -- and not apps[select].tag then
      delete_mode = 2
    elseif v == 'y' and delete_mode then
      os.remove(apps[select][1])
      rescan_dirs()
    end
    if delete_mode then
      delete_mode = delete_mode - 1
      if delete_mode == 0 then
        delete_mode = false
      end
    end
    select = math.min(select, #apps)
    select = math.max(1, select)
    if select < start then
      start = select
    elseif select - start >= NR then
      start = math.max(1, select - NR + 1)
    end
  end
  border()
end
