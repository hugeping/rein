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

function tune()
  mixer.voice('empty', 'empty')
  mixer.voice('bass', 'synth',
    { synth.WAVE_TYPE, synth. SQUARE },
    { synth.WAVE_WIDTH, 0 },
    { synth.VOLUME, 0.5 },
    { synth.LFO_SELECT, 0 },
    { synth.WAVE_TYPE, synth.SAW },
    { synth.LFO_WAVE_SIGN, -1 },
    { synth.LFO_FREQ, 15 },
    { synth.LFO_LEVEL, 100 },
    { synth.LFO_IS_ONESHOT, 1 },
    { synth.LFO_SELECT, 1 },
    { synth.LFO_WAVE_TYPE, synth.SAW },
    { synth.LFO_WAVE_SIGN, -1 },
    { synth.LFO_FREQ, 15 },
    { synth.LFO_LEVEL, 0.5 },
    { synth.LFO_IS_ONESHOT, 1 },
    { synth.LFO_TO_FREQ, 0 },
    { synth.LFO_TO_WIDTH, 1 })
  mixer.voice('square', 'synth', { synth.WAVE_TYPE, synth.SQUARE }, { synth.GLIDE_ON, 50 },
    { synth.WAVE_WIDTH, 0.7 } )
  mixer.voice('saw', 'synth',
    { synth.WAVE_TYPE, synth.SAW },
    { synth.ATTACK_TIME, 0.5 },
    { synth.DECAY_TIME, 0.5 },
    { synth.SUSTAIN_LEVEL, 0.5 },
    'delay',
    { synth.VOLUME, 1 },
    { synth.FEEDBACK, 0.5 },
    { synth.TIME, 0.2 },
    'dist',
    { synth.GAIN, 1})
  local voices = {'empty', 'empty', 'square', 'saw'}
  local pan = { 0, 0, -0.75, 0.75 }
  local song = [[
C-3 A0 | ... .. | C-4 .. | C-3 64
... .. | ... .. | G-3 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | D#4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | F-4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | ... .. | G-4 .. | ... ..
... .. | C-3 80 | F-4 45 | ... ..
C-3 A0 | ... .. | C-4 .. | ... ..
... .. | ... .. | G-4 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | D#4 .. | D-3 64
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | D-4 .. | D#3 64
... .. | ... .. | D#4 45 | ... ..
C-3 A0 | ... .. | G-3 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | C-4 .. | G#2 64
... .. | ... .. | G-3 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | D#4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | F-4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | ... .. | G-4 .. | ... ..
... .. | C-3 80 | F-4 45 | ... ..
C-3 a0 | ... .. | C-4 .. | ... ..
... .. | ... .. | G-4 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
C-3 A0 | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 a0 | ... .. | D#4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | ... .. | G-3 .. | ... ..
... .. | ... .. | D-4 45 | ... ..
]]
  return mixer.play(voices, pan, song, 16, -1)
end

mixer.volume(0.5)
tune()

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
  gfx.printf(108, 140, 1, VERSION)
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

  gfx.printf(0, 0, 15, "FPS:%d\nMouse:%d,%d %s\nKeys:%s\nInp:%s",
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
