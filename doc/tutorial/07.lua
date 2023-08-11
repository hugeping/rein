local x_pos = 128
local y_pos = 248
local width = 32
local speed = 4
local title, music
local ball_x, ball_y

local ball_dx = 2
local ball_dy = 2
local ball_r = 3

local x_min = width/2 + 4
local x_max = 255 - width/2 - 4

function clamp(v, min, max)
  if v < min then return min end
  if v > max then return max end
  return v
end

function draw()
  if title then
    gfx.printf(92, 128, 15, "GET READY!\n PRESS z")
    return 0
  end
  screen:rect(0, 0, 255, 255, 7) -- border
  screen:rect(2, 2, 253, 253, 7)
  for i = 10, 240, 15  do -- line
    screen:fill_rect(i, 127, i + 8, 128, 7)
  end
  screen:fill_rect(x_pos - width/2, y_pos, x_pos + width/2, y_pos + 2, 8)
  screen:fill_circle(ball_x, ball_y, ball_r, 9)
end

function init()
    title = true
    ball_y = 16
    ball_x = math.random(128) + 64
    ball_dx = math.random(2) == 1 and 1 or -1
    music = mixer.play('music', 1)
end

function update()
  if title then
    if input.keypress 'z' then
      title = false
      mixer.stop(music, 4)
    end
    return
  end
  if input.keydown 'left' then
    x_pos = x_pos - speed
  elseif input.keydown 'right' then
    x_pos = x_pos + speed
  end
  x_pos = clamp(x_pos, x_min, x_max)

  ball_x = ball_x + ball_dx
  ball_y = ball_y + ball_dy

  if ball_x >= 253 - ball_r or ball_x <= ball_r + 2 then
    ball_dx = -ball_dx
    mixer.play 'kick'
  end
  if ball_y < 2 + ball_r then
    ball_dy = -ball_dy
    mixer.play 'kick'
  end
  if ball_y >= y_pos - ball_r and ball_y < y_pos and
    ball_x >= x_pos - width/2 and ball_x < x_pos + width/2 then
    ball_dy = - ball_dy
    if input.keydown 'left' then ball_dx = ball_dx - 1 end
    if input.keydown 'right' then ball_dx = ball_dx + 1 end
    ball_dx = clamp(ball_dx, -3, 3)
    mixer.play 'kick'
  elseif ball_y > 250 then
    init()
  end
end

function run()
  while sys.running() do
    screen:clear(0)
    draw()
    update()
    gfx.flip(1/50)
  end
end

local __voices__ = [[
voice bdrum
box synth
# synth
volume 0.9

type square
width 0

attack 0.001
decay 0.07
sustain 0.5
release 0.1
set_sustain 0

lfo_type 0 saw
lfo_freq 0 17
lfo_low 0 180
lfo_high 0 20
lfo_set_loop 0 0
lfo_set_reset 0 1
lfo_assign 0 freq

lfo_type 1 saw
lfo_freq 1 17
lfo_low 1 0.5
lfo_high 1 0
lfo_set_loop 1 0
lfo_set_reset 1 1
lfo_assign 1 width

voice snare
box synth
# synth

volume 0.5
type band_noise

width 20000
offset 20000

attack 0.01
decay 0.11
sustain 0
release 0.1
set_sustain 0

lfo_type 0 saw
lfo_freq 0 12
lfo_low 0 20050
lfo_high 0 0
lfo_set_loop 0 0
lfo_set_reset 0 1
lfo_assign 0 freq


box synth
# synth
volume 0.8
type sin
set_fm 0
fmul freq 1
amp 1
width 0.5
offset 1
attack 0.01
decay 0.12
sustain 0
release 0
set_sustain 0
set_glide 0
glide_rate 0

lfo_type 0 saw
lfo_freq 0 10
lfo_low 0 150
lfo_high 0 80
lfo_set_loop 0 0
lfo_set_reset 0 1
lfo_assign 0 freq

box delay
# delay
volume 0.9
time 0.1
level 0.05
feedback 0.5

voice bass
box synth
# synth

volume 0.3
type saw
width 0

set_fm 0

fmul freq 1
amp 1

width 0.5
offset 1

attack 0.01
decay 0.15
sustain 0
release 0.1
set_sustain 0

set_glide 0
glide_rate 0

lfo_type 0 saw
lfo_freq 0 5
lfo_low 0 0.4
lfo_high 0 0
lfo_set_loop 0 0
lfo_assign 0 width

box synth
# synth

volume 0.3
type saw
width 0

set_fm 0

fmul freq 1.01
amp 1

width 0.45
offset 1

attack 0.01
decay 0.15
sustain 0
release 0.1
set_sustain 0

set_glide 1
glide_rate 500

lfo_type 0 saw
lfo_freq 0 5
lfo_low 0 0.4
lfo_high 0 0
lfo_set_loop 0 0
lfo_assign 0 width
]]

local __songs__ = [[
song kick
@tempo 16
@voice * bdrum
@vol * 1
| c-1 ff
| ... ..
| ... ..

song music
@voice 1 bdrum
@voice 2 snare
@voice 3 bass
@pan 1 0
@pan 2 -0.5
@pan 3 0.5
@vol 2 0.9
@tempo 15
| c-1 .. | ... .. | c-2 ..
| ... .. | ... .. | c-3 ..
| ... .. | c-2 .. | c-2 ..
| ... .. | ... .. | c-3 ..
| c-1 .. | ... .. | c-2 ..
| c-1 .. | ... .. | c-3 ..
| ... .. | c-2 .. | c-2 ..
| ... .. | ... .. | c-3 ..
| c-1 .. | ... .. | c-2 ..
| ... .. | ... .. | c-3 ..
| ... .. | c-2 .. | c-2 ..
| ... .. | ... .. | c-3 ..
| c-1 .. | ... .. | c-2 ..
| c-1 .. | ... .. | c-3 ..
| ... .. | c-2 .. | c-2 ..
| ... .. | ... .. | c-3 ..
| c-1 .. | ... .. | c-2 ..
| ... .. | ... .. | c-3 ..
| ... .. | c-2 .. | c-2 ..
| ... .. | ... .. | c-3 ..
| c-1 .. | ... .. | c-2 ..
| c-1 .. | ... .. | c-3 ..
| ... .. | c-2 .. | c-2 ..
| ... .. | ... .. | c-3 ..
]]

mixer.volume(0.7)
mixer.voices(__voices__)
mixer.songs(__songs__)

init()
run()
