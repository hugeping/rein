-- Игра "Пятнашки", 2024 Борис Тимофеев <btimofeev@emunix.org>

require "tiny"

board = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0}
zx, zy = 4, 4
dir = {
  left = {1, 0},
  right = {-1, 0},
  up = {0, 1},
  down = {0, -1}
}
GAME = 1
WIN = 2
state = GAME
W, H = screen:size()
tile_col = 15

function is_valid(x, y)
    return x > 0 and x < 5 and y > 0 and y < 5
end

function swap_empty_tile_with(x, y)
  local empty = get_index(zx, zy)
  local target = get_index(x, y)
  board[empty], board[target] = board[target], board[empty]
  zx, zy = x, y
end

function try_move_to(s)
  local x = zx + dir[s][1]
  local y = zy + dir[s][2]
  if is_valid(x, y) then
    swap_empty_tile_with(x, y)
  end
end

function get_xy(index)
  local x = 1 + (index - 1) % 4
  local y = floor((index + 3) / 4)
  return x, y
end

function get_index(x, y)
  return x + (y * 4) - 4
end

function board:shuffle()
  local dirs = {"left", "right", "up", "down"}
  local x, y, d

  for i = 1, 256 do
    repeat
      d = dirs[rnd(#dirs)]
      x = zx + dir[d][1]
      y = zy + dir[d][2]
    until is_valid(x, y)
    swap_empty_tile_with(x, y)
  end
end

function board.draw()
  local x, y = 38, 38
  for i = 1, 16 do
    num = board[i]
    if num >= 1 then
      draw_tile(x, y, tostring(num))
    end
    x = x + 45
    if i % 4 == 0 then
      x = 38
      y = y + 45
    end
  end
end

function draw_tile(x, y, text)
  local ex = x + 42
  local ey = y + 42

  line(x+2, y, ex-2, y, tile_col)
  line(x+2, ey, ex-2, ey, tile_col)
  line(x, y+2, x, ey-2, tile_col)
  line(ex, y+2, ex, ey-2, tile_col)
  fill_rect(x+1, y+1, ex-1, ey-1, tile_col)

  local tw, th = font:size(text)
  print(text, (ex+x-tw)/2, (ey+y-th)/2)
end

function draw_title()
    local text = "ПЯТНАШКИ"
    local w, h = font:size(text)
    print(text, (W - w)/2, 15)
end

function draw_win_message()
  if state == WIN then
    local text = "Вы выйграли! Нажмите SPACE"
    local w, h = font:size(text)
    print(text, (W - w)/2, 230)
  end
end

function is_win()
  for i = 1, 15 do
    if board[i] ~= i then
      return false
    end
  end
  return true
end

function update()
  if state == GAME then
    handle_game_keys()
  else
    if keypress('space') then
      restart()
    end
  end
end

function handle_game_keys()
  if keypress('up') then
    try_move_to('up')
  elseif keypress('down') then
    try_move_to('down')
  elseif keypress('left') then
    try_move_to('left')
  elseif keypress('right') then
    try_move_to('right')
  end

  if is_win() then
    state = WIN
  end
end

function restart()
  state = GAME
  board:shuffle()
end

function run()
  restart()
  while sys.running() do
    update()
    clear(16)
    draw_title()
    board.draw()
    draw_win_message()
    flip(1/30)
  end
end

run()
