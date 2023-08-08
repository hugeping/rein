local W, H = screen:size()
local FW, FH = font:size(" ")

local function scan_dir(apps)
  local ret = {}
  local dir = DATADIR..'/'..apps
  for _, n in ipairs(sys.readdir(dir)) do
    if n:find("%.[lL][uU][aA]$") then
      local name = n:gsub("%.[lL][uU][aA]$", "")
      table.insert(ret, { dir .. '/'.. n, name })
    end
  end
  table.sort(ret, function(a, b) return a[1] < b[1] end)
  return ret
end

local apps = scan_dir 'apps'

table.append(apps, table.unpack(scan_dir '../demo')) -- demos

local start = 1
local select = 1
local D = FH + 2
local NR = math.floor((H - 70)/ D) - 4

local function resume()
  gfx.border{ 0xde, 0xde, 0xde }
  mixer.done()
  mixer.init()
  sys.hidemouse(false)
  screen:nooffset()
  screen:noclip()
  sys.input(true) -- clear input
  gfx.win(W, H) -- resume screen
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
  gfx.printf(40, 4, 0, [[REIN Version:%s
(c)2023 Peter Kosyh
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
  rein <lua file>

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

local function border()
  local fl = math.floor(sys.time())%2
  gfx.border(fl == 1 and 7 or 12)
end

local help_mode

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

  gfx.printf(4, H - 2*FH, 0, [[F1-help Up,Down,z-run,x-edit
shift+esc-return to this launcher]])

  local xoff, yoff = 26, 72
  for i = start, #apps do
    local nr = i - start + 1
    local name = apps[i][2]
    if i == select then
      gfx.print("=>", xoff, yoff + nr*D, 1)
    end
    gfx.print(apps[i][2], xoff + 2*FW, yoff + nr*D, 1)
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
    elseif v == 'f1' then
      help_mode = true
    elseif v == 'z' or v == 'return' or v == 'space' then
      sys.exec(apps[select][1])
      sys.suspend()
      -- resumed
      resume()
    elseif v == 'x' then
      sys.input(true) -- clear input
      sys.exec("edit", apps[select][1])
      sys.suspend()
      -- resumed
      resume()
    end
    select = math.min(select, #apps)
    select = math.max(1, select)
    if select < start then
      start = select
    elseif select - start >= NR then
      start = start + 1
    end
  end
  border()
end
