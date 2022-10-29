local dump = require "dump"
local mixer = {}

function mixer.audio(t)
	local idx = 1
	local rc
	while true do
		rc = sys.audio(t, idx)
		if #t == rc + idx - 1 then
			return
		end
		idx = idx + rc
		coroutine.yield()
	end
end

function mixer.coroutine()
	while true do
		mixer.thr:poll() -- force show peer end error msg
		coroutine.yield()
	end
end

function mixer.add(fn)
	local c, e = dump.new(fn)
	if not c then
		error(e)
	end
	mixer.thr:write('add', c)
	return mixer.thr:read()
end

function mixer.stop()
	mixer.thr:write 'quit'
end

return mixer
