-- ---------------
--
-- Game "Catch me!" by Boris Timofeev <btimofeev@emunix.org>
--
-- Last update: 2023.08.19
--
-- ---------------

require 'tiny'

local STATE_TITLE = 1
local STATE_GAME = 2
local STATE_WIN = 3
local STATE_LOSE = 4

local game_state = STATE_TITLE

local board = {
  rows = 11,
  columns = 11,
  cell_radius = 9,
  cell_color = 15,
}

local cat = {
  col = nil,
  row = nil,
  start_col = 6,
  start_row = 6,
  is_look_to_left = false,
  spr = {},
}

local title = {
  gfx = nil,
  gfx_x = 20,
  gfx_y = 102,
  copyright = {
    text = "2023 - Boris Timofeev",
    y = 240,
  },
  start = {
    text = "Press SPACE to start",
    y = 180,
  },
  cat = {
    x = nil,
    y = nil,
    start_x = -10,
    start_y = 65,
    cur_path = 1,
    path = {
      { x = 28,  y = 89,  frames = 15 },
      { x = 29,  y = 89,  frames = 60 },

      { x = 50,  y = 70,  frames = 10 },
      { x = 75,  y = 93,  frames = 10 },

      { x = 100, y = 70,  frames = 10 },
      { x = 123, y = 93,  frames = 10 },

      { x = 150, y = 70,  frames = 10 },
      { x = 170, y = 103, frames = 10 },
      { x = 171, y = 103, frames = 60 },

      { x = 200, y = 78,  frames = 13 },
      { x = 218, y = 90,  frames = 7 },

      { x = 260, y = 70,  frames = 10 },
    },
    path_start_frame = nil,
  }
}

local direction = { "E", "NE", "NW", "W", "SW", "SE" }

local direction_diff = {
  odd = {
    E  = { col = 1, row = 0 },
    NE = { col = 0, row = -1 },
    NW = { col = -1, row = -1 },
    W  = { col = -1, row = 0 },
    SW = { col = -1, row = 1 },
    SE = { col = 0, row = 1 },
  },
  even = {
    E  = { col = 1, row = 0 },
    NE = { col = 1, row = -1 },
    NW = { col = 0, row = -1 },
    W  = { col = -1, row = 0 },
    SW = { col = 0, row = 1 },
    SE = { col = 1, row = 1 },
  }
}

local is_game_over_music_played = false

local frame = 1

function init_board()
  local dx, dy = 0, 0
  local space_size = 3

  for i = 1, board.rows do
    if is_even(i) then
      dx = dx + board.cell_radius
    end
    board[i] = {}
    for j = 1, board.columns do
      board[i][j] = {
        x = j * board.cell_radius * 2 + dx,
        y = i * board.cell_radius * 2 + dy,
        fill = false
      }
      dx = dx + space_size
    end

    dx = 0
    dy = dy + space_size
  end
end

function randomize_board()
  for i = 1, 10 do
    local row = rnd(board.rows)
    local col = rnd(board.columns)
    local is_start_pos_of_cat = row == cat.start_row and col == cat.start_col
    if not is_start_pos_of_cat  then
      board[row][col].fill = true
    end
  end
end

function draw_board()
  for i, row in ipairs(board) do
    for j, cell in ipairs(row) do
      if cell.fill then
        fill_circle(cell.x, cell.y, board.cell_radius, board.cell_color)
      end
      circle(cell.x, cell.y, board.cell_radius, board.cell_color)
    end
  end
end

function draw_cat()
  local offset = -7
  local cell = board[cat.row][cat.col]
  local spr = is_even(floor(sys.time())) and cat.spr[1] or cat.spr[2]
  if cat.is_look_to_left then
    spr = spr:scale(-1, 1)
  end
  spr:blend(screen, cell.x + offset, cell.y + offset)
end

function new_game()
  init_board()
  randomize_board()

  cat.col = cat.start_col
  cat.row = cat.start_row
  cat.is_look_to_left = false

  is_game_over_music_played = false
end

function check_click(x, y)
  for i, row in ipairs(board) do
    for j, cell in ipairs(row) do
      local is_clicked = sqrt((x-cell.x)^2 + (y-cell.y)^2) < board.cell_radius

      if is_clicked then
        local is_cell_without_cat = not (i == cat.row and j == cat.col)

        if is_cell_without_cat and cell.fill == false then
          cell.fill = true
          return true
        else
          return false
        end
      end
    end
  end
  return false
end

function clear_path_weights()
  for i = 1, board.rows do
    for j = 1, board.columns do
      board[i][j].pw = nil
    end
  end
end

function get_random_directions()
  local shuffled = {}
  for i = 1, 6 do
    local pos = rnd(1, #shuffled + 1)
    add(shuffled, pos, i)
  end
  return shuffled
end

function get_neighbor_cells_without_weight(row, col)
  local t = {}
  for _, v in ipairs(get_random_directions()) do
    local d = direction[v]
    local r, c = get_neighbor(row, col, d)
    local is_cell_valid = r > 0 and r <= board.rows and c > 0 and c <= board.columns
    if is_cell_valid and board[r][c].fill == false and board[r][c].pw == nil then
      add(t, { row = r, col = c })
    end
  end
  return t
end

function get_neighbor_cell_with_weight(row, col, weight)
  for i = 1, 6 do
    local d = direction[i]
    local r, c = get_neighbor(row, col, d)
    local is_cell_valid = r > 0 and r <= board.rows and c > 0 and c <= board.columns
    if is_cell_valid and board[r][c].fill == false and board[r][c].pw == weight then
      return { row = r, col = c }
    end
  end
end

function find_cat_move()
  local finish = find_near_finish_cell(cat.row, cat.col)
  if finish == nil then return nil end

  local pw = board[finish.row][finish.col].pw
  local move = finish
  while pw > 1 do
    pw = pw - 1
    move = get_neighbor_cell_with_weight(move.row, move.col, pw)
  end
  return move.row, move.col
end

function find_near_finish_cell(from_row, from_col)
  local reachable = {}
  local next = {}
  local weight = 0
  clear_path_weights()
  board[from_row][from_col].pw = weight
  add(next, {row = from_row, col = from_col})

  while #next ~= 0 do
    weight = weight + 1
    reachable = next
    next = {}

    for _, v in ipairs(reachable) do
      local cells = get_neighbor_cells_without_weight(v.row, v.col)

      for _, c in ipairs(cells) do
        board[c.row][c.col].pw = weight
        add(next, c)
        if is_finish_cell(c.row, c.col) then
          return c
        end
      end
    end
  end
end

function is_finish_cell(row, col)
  return row == 1 or col == 1 or row == board.rows or col == board.columns
end

function update()
  local mx, my, mb = mouse()

  if game_state == STATE_WIN or game_state == STATE_LOSE then
    if keypress('space') or (mb.left and (my > 245)) then
      game_state = STATE_GAME
      new_game()
    end
    return
  end

  if mb.left then
    local is_turn_completed = check_click(mx, my)
    if is_turn_completed  then
      local row, col = find_cat_move()
      check_game_result(row, col)
      if game_state ~= STATE_WIN then
        determine_cat_direction(row, col)
        cat.row = row
        cat.col = col
        mixer.play('cat_move')
      end
    end
  end
end

function determine_cat_direction(next_row, next_col)
  if is_even(cat.row) then
    cat.is_look_to_left = next_col <= cat.col
  else
    cat.is_look_to_left = next_col < cat.col
  end
end

function check_game_result(row, col)
  if row == nil or col == nil then
    game_state = STATE_WIN
  elseif row == 1 or col == 1 or row == board.rows or col == board.columns then
    game_state = STATE_LOSE
  end
end

function draw_game_result()
  if game_state == STATE_WIN then
    local text = 'You win! Press SPACE to restart.'
    print(text, get_x_to_center(text), 245)
    if not is_game_over_music_played then
      is_game_over_music_played = true
      mixer.play('win')
    end
  end

  if game_state == STATE_LOSE then
    local text = 'You lose! Press SPACE to restart.'
    print(text, get_x_to_center(text), 245)
    if not is_game_over_music_played then
      is_game_over_music_played = true
      mixer.play('lose')
    end
  end
end

function draw_title()
  title.gfx:blend(screen, title.gfx_x, title.gfx_y)
  print(title.copyright.text, get_x_to_center(title.copyright.text), title.copyright.y, 5)
  print(title.start.text, get_x_to_center(title.start.text), title.start.y)
  draw_title_cat_animation()
end

function draw_title_cat_animation()
  local spr = is_even(floor(sys.time())) and cat.spr[1] or cat.spr[2]
  local c = title.cat
  local x, y = 0, 0

  if c.x == nil or c.y == nil then
    c.cur_path = 1
    c.x = c.start_x
    c.y = c.start_y
  end

  if c.path_start_frame == nil then
    c.path_start_frame = frame
  end

  if c.cur_path <= #c.path then
    local to = c.path[c.cur_path]
    local delta = frame - c.path_start_frame
    if delta == 0 then delta = 1 end

    x = lerp(c.x, to.x, delta / to.frames)
    y = lerp(c.y, to.y, delta / to.frames)
    spr:blend(screen, x, y)

    if x == to.x and y == to.y then
      c.cur_path = c.cur_path + 1
      c.path_start_frame = nil
      c.x = to.x
      c.y = to.y
    end
  else
    c.x = nil
    c.y = nil
  end
end

function lerp(s, e, t)
  return s + (e - s) * t
end

function update_title()
  local mx, my, mb = mouse()

  if keypress('space') or (mb.left) then
    game_state = STATE_GAME
  end
end

function run()
  new_game()
  while sys.running() do
    clear(16)
    if game_state == STATE_TITLE then
      draw_title()
      update_title()
    else
      draw_board()
      draw_cat()
      draw_game_result()
      update()
    end
    flip(1/30)
    frame = frame + 1
  end
end

function is_even(num)
  return num % 2 == 0
end

function get_neighbor(row, col, direction)
  local parity = is_even(row) and "even" or "odd"
  local diff = direction_diff[parity][direction]
  return row + diff.row, col + diff.col
end

function get_x_to_center(text)
  local W, H = screen:size()
  local w, h = font:size(text)
  return (W - w)/2
end

function get_title_gfx()
  return loadspr [[
-----5---------f--
----5555555-----------------------------------------------------------------------------------------------
-5555fffff55-----------------------------------------------------------------------------------------555--
55fffffffff5-----------------5555--------------------5555--------------------------------------------5f55-
5ffffffffff5----------------55ff5------------------555ff5-------------------------------------------55ff55
5fff5555fff5----------------5fff5------------------5ffff5-------------------------------------------5ffff5
5fff5--5ff55----------------5fff5------------------5ffff5-------------------------------------------5ffff5
5fff5--5555-------5555------5fff5------------------55fff5-------------------------------------------5ffff5
5fff5---------55555ff5------5fff5---------5555555---5fff555555-----------5555---5555-----5555-------5ffff5
5fff5---------5ffffff55----55fff55555--5555fffff55--5fff5ffff55----------5ff5---5ff5--5555ff555-----5fff55
5fff5---------5fffffff5---55ffffffff5--5fffffffff5--5fffffffff5----------5ff55555ff5-55fffffff55----5fff5-
5fff5---------5555ffff55--5fffffffff5-55fffffffff5--5fffff5fff5----------55fff5fff55-5fffffffff5----5fff5-
5fff5-------------5ffff5--5ffffffff55-5fff5555fff5--5fff555fff5-----------5fff5fff5--5fff555fff5----5ff55-
5fff5---------555555fff5--555fff5555--5fff5--5ff55--5fff5-5fff5----------55fff5fff55-5fff5-5fff5----5ff5--
5fff5--------55ffffffff55---5fff5-----5fff5--5555---5fff5-5fff5----------5fffffffff5-5fff555ff55----5ff5--
5fff55-------5fff555ffff5---5fff5-----5fff5---------5fff5-5fff5----------5fffffffff5-5fff5fff55-----5555--
5ffff5-------5fff5-5ffff5---5fff5-----5fff55--------5fff5-5fff5----------5fff5f5fff5-5fff55555-------55---
55fff5555555-5fff5555fff5---5fff555---55fff5555555--5fff5-5fff5----------5fff5f5fff5-5ffff5---------------
-5fffffffff5-5ffffff5fff5---5fffff5----5fffffffff5--5fff5-5fff5----------5fff5f5fff5-5ffff555555----5555--
-5fffffffff5-5ffffff5fff5---5fffff5----5fffffffff5--5fff5-5fff5----------5fff555fff5-55ffffffff5----5ff5--
-55fffff5555-55fff555ff55---55fff55----55fffff5555--5ff55-5fff5----------5ff55-5ff55--55ffff5555----55f5--
--5555555-----55555-5555-----55555------5555555-----5555--5ff55----------5555--5555----555555--------555--
----------------------------------------------------------5555--------------------------------------------
]]
end

cat.spr = { [[
0---45-7-------f--
---------------
-----55-----55-
-----5f5---5f5-
-----5ff555ff5-
----5fff4f4fff5
-55-5fffffffff5
5f5-5fff0ff0ff5
545-5ffff77fff5
5f5555ff7777f5-
54f4f555555555-
-5f4f4ffffff5--
-5ffffffffff5--
-5ffffffffff5--
-575755557575--
]], [[
0---45-7-------f--
---------------
-----55-----55-
-----5f5---5f5-
-----5ff555ff5-
-55-5fff4f4fff5
5f5-5fffffffff5
545-5ff0ff0fff5
5f5-5fff77ffff5
545555f7777ff5-
5ff4f555555555-
-5f4f4ffffff5--
-5ffffffffff5--
-5ffffffffff5--
-575755557575--
]]
}

for i=1, #cat.spr do
  cat.spr[i] = loadspr(cat.spr[i])
end

title.gfx = get_title_gfx():scale(2, 2)

local __voices__ = [[
voice 1
box synth
# synth
volume 0.5
type square
width 0.3

attack 0.01
decay 0.01
sustain 0.5
release 0.01

box dist
# dist
volume 0.5
gain 0.3

voice 2
box synth
# synth
volume 0.5
type square

width 0.2

attack 0.01
decay 0.1
sustain 0.5
release 0.3

set_glide 1
glide_rate 50

lfo_type 0 saw
lfo_freq 0 60
lfo_low 0 0
lfo_high 0 10
lfo_assign 0 freq
]]

local __songs__ = [[
song cat_move
@voice * 1
@tempo 5
| f-2 ..
| ... ..
| ... ..
| ... ..
| ... ..
| ... ..

song lose
@voice * 2
@tempo 10
@pan 1 -0.5
@pan 2 0.5
| f-3 ff | ... ..
| ... .. | e-3 e0
| ... .. | === ..
| ... .. | f-2 c0
| g-2 b0 | === ..
| === .. | d-2 a0
| c-2 90 | === ..
| ... .. | ... ..
| ... .. | ... ..
| ... .. | ... ..
| ... .. | ... ..
| ... .. | ... ..
| === .. | ... ..

song win
@voice * 2
@tempo 10
@pan 1 -0.5
@pan 2 0.5
| c-4 .. | ... ..
| e-4 .. | c-4 ..
| ... .. | e-4 ..
| g-4 .. | d-4 ..
| f-4 .. | g-4 ..
| a-4 .. | a-4 ..
| ... .. | c-4 ..
| c-5 .. | d-4 ..
| d-5 .. | f-4 ..
| e-5 .. | c-4 ..
| === .. | ... ..
| ... .. | ... ..
]]

mixer.voices(__voices__)
mixer.songs(__songs__)

sys.title("Catch me!")
gfx.icon(cat.spr[1])

run()
