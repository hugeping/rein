local sfx = {
}

local SR = 44100
local TWO_PI_BY_SR = 2 * math.pi / SR

function sfx.sin(t, freq)
	return math.sin(TWO_PI_BY_SR * freq * t)
end

function sfx.dsf(t, freq, modscale, modamp, width)
	local f1 = TWO_PI_BY_SR * freq * t
	local f2 = modscale * f1
	local ww = width * width
	local e1 = math.sin(f1) - width * modamp * math.sin(f1 - f2)
	local e2 = 1 + ww - 2 * width * modamp * math.cos(f2)
	return e1 / e2
end

function sfx.saw(t, freq, width)
	width = width or 0.5
	return sfx.dsf(t, freq, 1, 1, width)
end

function sfx.square(t, freq, width)
	width = width or 0.5
	return sfx.dsf(t, freq, 2, 1, width)
end

return sfx
