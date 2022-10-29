-- https://github.com/true-grue/libzvuk/blob/main/libzvuk.ipynb
-- Adopted by Peter Kosyh, original code by Peter Sovietov

local sfx = {
}

local SR = 44100
local TWO_PI = 2 * math.pi
local INV_SR = 1 / SR
local TWO_PI_BY_SR = TWO_PI / SR

local floor = math.floor

function sfx.sec(x)
	return floor(x * SR)
end

function sfx.mix(x, y, a)
	return x * (1 - a) + y * a
end

function sfx.hz(t, freq)
	return TWO_PI_BY_SR * freq * t
end

local NOTES = {
	['c-'] = 0,
	['c#'] = 1,
	['d-'] = 2,
	['d#'] = 3,
	['e-'] = 4,
	['f-'] = 5,
	['f#'] = 6,
	['g-'] = 7,
	['g#'] = 8,
	['a-'] = 9,
	['a#'] = 10,
	['b-'] = 11
}

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
