local W, H = screen:size()
local sprites -- loaded in the end of file

-- press F8 to edit gfx
-- press F9 to edit sfx
-- save & shift-esc to apply changes

function run()
  local y, dx = 128, 8
  while sys.running() do
    screen:clear(15)
    gfx.spr(sprites, 0, (W - 32)/2, y, 4, 1)
    y = y + dx
    if y >= H - 8 or y <= 0 then
      dx = -dx
      mixer.play 'boom'
    end
    gfx.flip(1/30)
  end
end

local __spr__ = [[
---3-------bc---
b3--b3-bbbb-b3---b3---bbbb3---------
b3--b3-b333-b3---b3---b3-b3---------
b3--b3-b3---b3---b3---b3-b3-------c-
bbbbb3-bbbb-b3---b3---b3-b3------ccc
b333b3-b333-b3---b3---b3-b3-------c-
b3--b3-b3---b3---b3---b3-b3---------
b3--b3-bbbb-bbbb-bbbb-bbbb3---------
33--33-3333-3333-3333-33333---------
]]

local __voices__ = [[
voice bass
box synth
fmul freq 0.5
type square
width 0
decay 0.2
sustain 0
release 0.01
volume 0.9
lfo_assign 0 freq
lfo_type 0 saw
lfo_freq 0 15
lfo_low 0 100
lfo_high 0 -100
lfo_set_loop 0 0
lfo_assign 1 width
lfo_type 1 saw
lfo_freq 1 15
lfo_low 1 0.5
lfo_high 1 -0.5
lfo_set_loop 1 0
]]

local __songs__ = [[
song boom
@tempo 16
@voice * bass
@vol * 0.8
C-3
...
...
]]

sprites = gfx.new(__spr__)

mixer.voices(__voices__)
mixer.songs(__songs__)

run()
