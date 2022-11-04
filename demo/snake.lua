sys.title("Snake Game")
gfx.border(1)

local gamecycle = false
local gameover = false
local delay = 10
local step = 0
local score = 0
local lifes = 5
local snake = {}
local increase = 0
local apple = {}
local dx = 1
local dy = 0

function newsnake()
	dx, dy = 1, 0
	snake = {}
	for i = 0, 10 do
		table.insert(snake, {x=25+i, y=31})
	end
end

function newapple()
	while true do
		apple.x = math.floor(math.random() * 64)
		apple.y = math.floor(math.random() * 62)
		local stop = true
		for i = 1, #snake do
			if apple.x == snake[i].x and apple.y == snake[i].y then
				stop = false
			end
		end
		if stop then return end
	end
end

function collide(x, y)
	for i = 1, #snake-2 do
		if snake[i].x == x and snake[i].y == y then
			return true
		end
	end
	return false
end

function eat(x, y)
	if apple.x == x and apple.y == y then
		score = score + 5
		if score % 100 == 0 then lifes = lifes + 1 end
		newapple()
		increase = 10
	end
end

function death()
	lifes = lifes - 1
	if lifes == 0 then
		gameover = true
	end
	newsnake()
	newapple()
	delay = 10
end

function makestep(dx, dy)
	if delay > 0 then
		delay = delay - 1
		return
	end
	local nx = snake[#snake].x+dx
	local ny = snake[#snake].y+dy
	if collide(nx, ny) then
		death()
		return
	end
	if nx > 63 then
		death()
		return
	end
	if nx < 0 then
		death()
		return
	end
	if ny > 61 then
		death()
		return
	end
	if ny < 0 then
		death()
		return
	end
	eat(nx, ny)
	if increase > 0 then
		table.insert(snake, {x=nx, y=ny})
		increase = increase - 1
	else
		for i = 1, #snake-1 do
			snake[i] = snake[i+1]
		end
		snake[#snake] = {x=nx, y=ny}
	end
end

function titlescreen()
	gfx.print("Snake game", 86, 1, 11)
	gfx.print("by Spline", 90, 13, 3)
	gfx.print("2022", 112, 25, 5)
	gfx.print("Press SPACE to start game", 29, 247, 7)
	local a, b = sys.input()
	if a == "keydown" and b == "space" then
		gamecycle = true
	end
end

function gamestep()
	screen:clear(apple.x*4, apple.y*4+8, 3, 3, 4)
	if delay == 0 or delay % 2 == 0 then
		for k, v in pairs(snake) do
			if k < #snake then
				screen:clear(v.x*4, v.y*4+8, 3, 3, 3)
			else
				screen:clear(v.x*4, v.y*4+8, 3, 3, 11)
			end
		end
	end
	screen:clear(0, 0, 256, 8, 2)
	local status = "Life: " .. tostring(lifes) .. " Score: " .. tostring(score)
	local w, h = font:size(status)
	gfx.print(status, (256-w)/2, 0, 7)
	local a, b = sys.input()
	if a == "keydown" then
		if b == "right" then
			if snake[#snake-1].x ~= snake[#snake].x+1 then
				dx = 1
				dy = 0
			end
		elseif b == "left" then
			if snake[#snake-1].x ~= snake[#snake].x-1 then
				dx = -1
				dy = 0
			end
		elseif b == "down" then
			if snake[#snake-1].y ~= snake[#snake].y+1 then
				dx = 0
				dy = 1
			end
		elseif b == "up" then
			if snake[#snake-1].y ~= snake[#snake].y-1 then
				dx = 0
				dy = -1
			end
		end
	end
	if step == 5 then
		makestep(dx, dy)
		step = 0
	end
	step = step + 1
end

function gameoverscreen()
	screen:clear(0)
	gfx.print("GAME OVER", 90, 120, 4)
	local scoretext = "Your score: " .. tostring(score)
	local w, h = font:size(scoretext)
	gfx.print(scoretext, (256-w)/2, 129, 7)
	gfx.print("Press SPACE to start game", 29, 247, 7)
	local a, b = sys.input()
	if a == "keydown" and b == "space" then
		gamecycle = true
		gameover = false
		lifes = 5
		score = 0
	end
end

newsnake()
newapple()

while true do
	screen:clear(0)

	if gamecycle then
		if gameover then
			gameoverscreen()
		else
			gamestep()
		end
	else
		titlescreen()
	end

	gfx.flip(1/60)
end

