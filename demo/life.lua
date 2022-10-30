sys.title('Conway\'s Game of Life')

local frames = 0
local generation = 0
local population = 0
local world = {}
local shadow1 = {}
local shadow2 = {}
local shadow3 = {}
local next_world = {}
local help = false
local life = false
local i = 0
local t = 0
local c = gfx.new(4, 4)
local s1 = gfx.new(4, 4)
local s2 = gfx.new(4, 4)
local s3 = gfx.new(4, 4)


local function fill_cell(pixels, alpha)
  pixels:clear(0)
  pixels:fill(1, 1, 3, 3, {48, 140, 32, alpha})
end

local function check_coord(i, j)
  if i == 0 then i = 64 end
  if i == 65 then i = 1 end
  if j == 0 then j = 62 end
  if j == 63 then j = 1 end
  return i, j
end

local function check_click(mx, my)
  if math.floor(my/4+1) > 0 and math.floor(my/4+1) < 63 and
    math.floor(mx/4+1) > 0 and math.floor(my/4+1) < 65 then
    return true
  end
  return false
end

local function flash(mx, my)
  for x = mx-1, mx+1 do
    for y = my-1, my+1 do
      local i, j = check_coord(x, y)
      shadow2[j][i] = 1
    end
  end
end

fill_cell(s1, 96)
fill_cell(s2, 64)
fill_cell(s3, 48)

for y = 1, 62 do
  local line = {}
  for x = 1, 64 do
    table.insert(line, 0)
  end
  table.insert(world, line)
  table.insert(next_world, {})
  table.insert(shadow1, {})
  table.insert(shadow2, {})
  table.insert(shadow3, {})
end

local function live_step()
  population = 0
  for x = 1, 64 do
    for y = 1, 62 do
      local count = 0
      for x1 = x-1, x+1 do
        for y1 = y-1, y+1 do
          if not (x1 == x and y1 == y) then
            local i, j = check_coord(x1, y1)
            if world[j][i] == 1 then
              count = count + 1
            end
          end
        end
      end
      if count == 3 then
        next_world[y][x] = 1
        population = population + 1
      end
      if count == 2 and world[y][x] == 1 then
        next_world[y][x] = 1
        population = population + 1
      end
      if count < 2 or count > 3 then
        next_world[y][x] = 0
      end
    end
  end
  for x = 1, 64 do
    for y = 1, 62 do
      world[y][x] = next_world[y][x]
    end
  end
  generation = generation + 1
end

while true do
  screen:clear(0)
  if not help then
    for x = 1, 64 do
      for y = 1, 62 do
        fill_cell(c, math.abs(math.sin(t/15+x*y)/2*48+211))
        if world[y][x] == 1 then
          c:blend(screen, x*4-4, y*4-4)
        elseif shadow1[y][x] == 1 then
          s1:blend(screen, x*4-4, y*4-4)
        elseif shadow2[y][x] == 1 then
          s2:blend(screen, x*4-4, y*4-4)
        elseif shadow3[y][x] == 1 then
          s3:blend(screen, x*4-4, y*4-4)
        end
      end
    end
  else
    print("[LMB]   - set cell\n[RBM]   - unset cell\n[Space] - start evolution\n[Enter] - evolution step\n[C]     - clear field\n[R]     - random field", 1, 1, 7)
  end
  local mx, my, mb = input.mouse()
  local a, b = sys.input()
  if not help and mb.left and check_click(mx, my) and world[math.floor(my/4+1)][math.floor(mx/4+1)] == 0 then
    world[math.floor(my/4+1)][math.floor(mx/4+1)] = 1
    flash(math.floor(mx/4+1), math.floor(my/4+1))
    population = population + 1
  elseif not help and mb.right and check_click(mx, my) and world[math.floor(my/4+1)][math.floor(mx/4+1)] == 1 then
    world[math.floor(my/4+1)][math.floor(mx/4+1)] = 0
    shadow1[math.floor(my/4+1)][math.floor(mx/4+1)] = 0
    shadow2[math.floor(my/4+1)][math.floor(mx/4+1)] = 0
    shadow3[math.floor(my/4+1)][math.floor(mx/4+1)] = 0
    population = population - 1
  end
  if help and a == 'keydown' then
    if b == 'escape' then
      help = false
    end
  end
  if not help and a == 'keydown' then
    if b == 'space' then
      for x = 1, 64 do
        for y = 1, 62 do
          shadow1[y][x] = 0
          shadow2[y][x] = 0
        end
      end
      life = not life
      generation = 0
    end
    if b == 'c' then
      for x = 1, 64 do
        for y = 1, 62 do
          world[y][x] = 0
        end
      end
      population = 0
    end
    if b == 'r' then
      for x = 1, 64 do
        for y = 1, 62 do
          world[y][x] = math.floor(math.random() + 0.5)
          if world[y][x] == 1 then
            flash(x, y)
          end
        end
      end
    end
    if b == 'return' then
      live_step()
    end
    if b == 'h' then
      help = true
    end
  end
  if i == 0 then
    for x = 1, 64 do
      for y = 1, 62 do
        shadow3[y][x] = shadow2[y][x]
        shadow2[y][x] = shadow1[y][x]
        shadow1[y][x] = world[y][x]
      end
    end
    if life then
      live_step()
    end
  end
  screen:clear(0, 256-8, 256, 256-8, 7)
  printf(0, 256-8, 0, "Gen: %d | Pop: %d", generation, population)
  if help then
    print("[Esc]Quit", 256-8*9-1, 256-8, 0)
  else
    print("[H]elp", 256-8*6-1, 256-8, 0)
  end
  gfx.flip(1/60)
  i = i + 1
  if i == 8 then i = 0 end
  t = t + 1
end

