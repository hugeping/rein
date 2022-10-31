local spr = {[[
---------------*
  -**-**--
  *--*--*-
  *-----*-
  -*---*--
  --*-*---
  ---*----
  --------
  --------
]], [[
---------------*
  -**-**--
  *******-
  *******-
  -*****--
  --***---
  ---*----
  --------
  --------
]]
}
local w, h = screen:size()
stars = {}

for i=1, #spr do
  spr[i] = gfx.new(spr[i])
end

for i=1, 128 do
  table.insert(stars, {
    x = math.random(w),
    y = math.random(h),
    c = math.random(16),
    s = math.random(8),
  })
end

local frames = 0
local txt = ''

local function showkeys()
  local t = ''
  local k = { 'left', 'right', 'up', 'down', 'space', 'z', 'x' }
  for _, v in ipairs(k) do
    if input.keydown(v) then
      t = t .. v .. ' '
    end
  end
  return t
end

function tune(nr)
  local sfx = require "sfx"
  local voices = {
    sfx.SquareVoice(),
    sfx.SawVoice(),
  }
  local pans = { -0.5, 0.5 };
  local song = [[
C-4 .. | C-3 64
G-3 45 | ... ..
C-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
D-4 45 | ... ..
D#4 .. | ... ..
D-4 45 | ... ..
D#4 .. | ... ..
D#4 45 | ... ..
F-4 .. | ... ..
D#4 45 | ... ..
G-4 .. | ... ..
F-4 45 | ... ..
C-4 .. | ... ..
G-4 45 | ... ..
C-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
D-4 45 | ... ..
D#4 .. | D-3 64
D-4 45 | ... ..
D#4 .. | ... ..
D#4 45 | ... ..
D-4 .. | D#3 64
D#4 45 | ... ..
G-3 .. | ... ..
D-4 45 | ... ..
C-4 .. | G#2 64
G-3 45 | ... ..
C-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
D-4 45 | ... ..
D#4 .. | ... ..
D-4 45 | ... ..
D#4 .. | ... ..
D#4 45 | ... ..
F-4 .. | ... ..
D#4 45 | ... ..
G-4 .. | ... ..
F-4 45 | ... ..
C-4 .. | ... ..
G-4 45 | ... ..
C-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
C-4 45 | ... ..
D-4 .. | ... ..
D-4 45 | ... ..
D#4 .. | ... ..
D-4 45 | ... ..
D#4 .. | ... ..
D#4 45 | ... ..
D-4 .. | ... ..
D#4 45 | ... ..
G-3 .. | ... ..
D-4 45 | ... ..
]]
  local song = sfx.parse_song(song)
  nr = nr or -1
  while nr ~= 0 do
    sfx.play_song(voices, pans, song)
    if nr ~= -1 then
      nr = nr - 1
    end
  end
end

mixer.volume(0.5)
mixer.new(tune)

local s = gfx.new
[[
--------8
------8
-----8-
----8--
---8---
--8----
-8-----
8------
]];

function draw_text(txt, xx, yy, scale, col)
  local s = font:text(txt, 7)
  local w, h = s:size()
  local r, g, b, a
  for y=0,h-1 do
    for x=0,w-1 do
      r, g, b, a = s:val(x, y)
      if a > 128 then
        screen:fill(xx + x*scale, yy + y*scale, scale, scale, col)
      end
    end
  end
end

local fps = 0

while true do
  screen:clear(0)
  draw_text("REIN", 70, 100, 4, s)
  printf(108, 140, 1, VERSION)
  screen:offset(math.floor(math.sin(frames * 0.1)*6), math.floor(math.cos(frames * 0.1)*6))
  spr[math.floor(frames/10)%2+1]:blend(screen, 240, 0)

  local mx, my, mb = input.mouse()
  local a, b = sys.input()

  if a == 'text' then
    txt = txt .. b
  elseif a == 'keydown' and b == 'return' then
    txt = txt .. '\n'
  elseif a == 'keydown' and b == 'backspace' then
    txt = ''
  end

  printf(0, 0, 15, "FPS:%d\nMouse:%d,%d %s\nKeys:%s\nInp:%s",
    fps, mx, my, mb.left and 'left' or '',
    showkeys(), txt..'\1')

  for k, v in ipairs(stars) do
    screen:pixel(v.x, v.y, v.c)
    stars[k].y = v.y + v.s
    if stars[k].y > h then
      stars[k].y = 0
      stars[k].x = math.random(w)
    end
  end
  fps = gfx.flip(1/50)
  frames = frames + 1
end
