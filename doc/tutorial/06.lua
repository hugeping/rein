local x_pos = 128
local y_pos = 248
local width = 32
local speed = 4

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
  screen:rect(0, 0, 255, 255, 7) -- border
  screen:rect(2, 2, 253, 253, 7)
  for i = 10, 240, 15  do -- line
    screen:fill_rect(i, 127, i + 8, 128, 7)
  end
  screen:fill_rect(x_pos - width/2, y_pos, x_pos + width/2, y_pos + 2, 8)
  screen:fill_circle(ball_x, ball_y, ball_r, 9)
end

function init()
    ball_y = 16
    ball_x = math.random(128) + 64
    ball_dx = math.random(2) == 1 and 1 or -1
end

function update()
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
voice kick
box synth
# synth
volume 0.8
type noise
set_fm 0
fmul freq 3
amp 1
width 0.7
offset 1
attack 0.01
decay 0.01
sustain 0
]]

local __songs__ = [[
song kick
@tempo 16
@voice * kick
@vol * 1
C-3 ff
...
...
]]

mixer.volume(0.7)
mixer.voices(__voices__)
mixer.songs(__songs__)

init()
run()
