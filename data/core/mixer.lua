local mixer = {
	chans = {};
}

function mixer.thread()
	while true do
		local t = {}
		for i = 1,4096,2 do
			local mix = {}
			local k, n = 1, #mixer.chans
			local ll, rr = 0, 0
			while k<=n do
				local fn = mixer.chans[k]
				local st, l, r = coroutine.resume(fn)
				if not st or not l then
					table.remove(mixer.chans, k)
					n = n - 1
					if not st then
						core.err(l..'\n'..debug.traceback(fn))
					end
				else
					k = k + 1
					ll = ll + l
					rr = rr + r
				end
			end
			if mixer.chans[1] then
				t[i] = ll / #mixer.chans
				t[i+1] = rr / #mixer.chans
			else
				break
			end
		end
		if t[1] then
			mixer.audio(t)
		end
		coroutine.yield()
	end
end

function mixer.audio(t)
	local idx = 1
	local rc
	while true do
		rc = system.audio(t, idx)
		if #t == rc + idx - 1 then
			return
		end
		idx = idx + rc
		coroutine.yield()
	end
end

function mixer.check(fn)
	if not fn then
		return #mixer.chans > 0
	end
	for k, v in ipairs(mixer.chans) do
		if v == fn then
			return true
		end
	end
end

function mixer.stop(fn)
	if not fn then
		mixer.chans = {}
	end
	for k, v in ipairs(mixer.chans) do
		if v == fn then
			table.remove(mixer.chans, k)
			return
		end
	end
end

function mixer.add(fn)
	local f, e
	if type(fn) == 'table' then -- rawdata
		local stereo = false
		if type(fn[1]) == 'table' then
			stereo = true
		end
		f, e = coroutine.create(function()
			for i=1,#fn do
				if stereo then
					coroutine.yield(fn[i][1], fn[i][2])
				else
					coroutine.yield(fn[i], fn[i])
				end
			end
		end)
	else
		f, e = coroutine.create(fn)
	end
	if not f then
		return f, e
	end
	table.insert(mixer.chans, f)
	return f
end

return mixer
