local dump = require "dump"
local CHUNK = 8192
local CHANNELS = 8

local mixer = {
	chans = {
	};
	buff = {
		channels = 2,
		head = 1,
		tail = 1,
		size = CHUNK,
		used = 0
	};
}

function mixer.fill()
	local size = #mixer.buff
	local b = mixer.buff
	local pos = b.tail
	for i = 1, b.size-b.used, b.channels do
		local ll, rr = 0, 0
		local n = 0
		for k = 1, CHANNELS do
			local fn = mixer.chans[k]
			if fn then
				local st, l, r = coroutine.resume(fn)
				r = r or l
				if not st or not l then
					mixer.chans[k] = false -- stop it
					if not st then
						error(l..'\n'..debug.traceback(fn))
					end
				else
					n = n + 1
					ll = ll + l
					if b.channels == 2 then
						rr = rr + r
					end
				end
			end
		end
		if n == 0 then -- no data
			break
		end
		b[pos] = ll / n
		pos = (pos % b.size) + 1
		b.used = b.used + 1
		if b.channels == 2 then
			b[pos] = rr / n
			pos = (pos % b.size) + 1
			b.used = b.used + 1
		end
	end
	b.tail = pos
end

function mixer.audio(t)
	local rc
	local b = mixer.buff
	if b.used == 0 then
		return
	end
	repeat
		local len = b.size - b.head + 1
		if len > b.used then
			len = b.used
		end
		local rc = sys.audio(b, b.head, len)
		b.used = b.used - rc
		b.head = ((b.head + rc) % b.size)
		b.head = (b.head == 0) and 1 or b.head
	until b.used == 0 or rc == 0
end

function mixer.add(fn)
	local f, e = coroutine.create(fn)
	if not f then
		error(e)
	end
	for i = 1, CHANNELS do
		if not mixer.chans[i] then
			mixer.chans[i] = f
			return i
		end
	end
end

function mixer.thread()
	print "mixer start"
	while true do
		local r, v
		r, v = thread:read(1/20)
		if r == 'quit' then
			break
		elseif r == 'add' then
			v = dump.new(v) -- function
			local h = mixer.add(v)
			thread:write(h)
		end
		mixer.fill()
		mixer.audio(t)
	end
	print "mixer finish"
end

mixer.thread()
