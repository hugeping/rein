-- https://github.com/true-grue/libzvuk/blob/main/libzvuk.ipynb
-- Adopted by Peter Kosyh, original code by Peter Sovietov

if unpack then
	table.unpack = unpack
end
require "std"
local sfx = {
}

local PI = math.pi
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

function sfx.get_midi_note(m)
	return 440 * 2 ^ ((m - 69) / 12)
end

function sfx.get_note(name)
	local n, o = name:sub(1, 2):lower(), tonumber(name:sub(3))
	return sfx.get_midi_note(NOTES[n] + 12 * (o + 2))
end

function sfx.parse_data(text)
	local cols = text:split(" ")
	local data = { not cols[1]:startswith "." and sfx.get_note(cols[1])
		or false }
	for i = 2, #cols do
		table.insert(data, not cols[i]:startswith "." and
			tonumber(cols[i], 16) or false)
	end
	return data
end

function sfx.parse_row(text)
	local ret = {}
	for _, v in ipairs(text:split("|")) do
		v = sfx.parse_data(v:strip())
		table.insert(ret, v)
	end
	return ret
end

function sfx.parse_song(text)
	local ret = {}
	text = text:strip()
	for row in text:lines() do
		table.insert(ret, sfx.parse_row(row:strip()))
	end
	return ret
end

function sfx.sin(t, freq)
	return math.sin(TWO_PI_BY_SR * freq * t)
end

function sfx.dsf(freq, mod_factor, width)
	local mfreq = mod_factor * freq
	local num = math.sin(freq) - width * math.sin(freq - mfreq)
	return num / (1 + width * (width - 2 * math.cos(mfreq)))
end

function sfx.dsf2(freq, mod_factor, width)
	local mfreq = mod_factor * freq
	local num = math.sin(freq) * (1 - width * width)
	return num / (1 + width * (width - 2 * math.cos(mfreq)))
end

function sfx.saw(freq, width)
	return sfx.dsf(freq, 1, width or 0.5)
end

function sfx.square(freq, width)
	return sfx.dsf(freq, 2, width or 0.5)
end

function sfx.lfsr(state, bits, taps)
	local x = 0
	for _, t in ipairs(taps) do
		x = bit.bxor(x, bit.bshr(state, t))
	end
	return bit.bor(bit.bshr(state, 1),
		(bit.bshl(bit.band(bit.bnot(x), 1), bits - 1)))
end

function sfx.envelope(t, deltas, levels, level_0, func)
	level_0 = level_0 or 0
	func = func or sfx.mix
	local t_0 = 0
	for dt, level in table.zip(deltas, levels) do
		if t <= t_0 + dt then
			return func(level_0, level, (t - t_0) / dt)
		end
		t_0, level_0 = t_0 + dt, level
	end
	return level_0
end

function sfx.step(x, y, a)
	return y
end

function sfx.delay(buf, pos, x, level, fb)
	fb = fb or 0.5
	local old = buf[pos]
	local y = x + old * level
	buf[pos] = old * fb + x
	pos = (pos % #buf) + 1
	return y, pos
end

function sfx.set_stereo(x, pan)
	pan = (pan + 1) / 2
	return x * ((1 - pan)^0.5), x * (pan^0.5)
end

local phasor = {}
phasor.__index = phasor

function phasor:reset()
	self.phase = 0
end

function phasor:next(freq)
	local p = self.phase
	self.phase = (self.phase + (2 * PI / SR) * freq) % (4 * PI)
	return p
end

function sfx.Phasor()
	local s = {
		phase = 0;
	}
	setmetatable(s, phasor)
	return s
end

local envelop = {}
envelop.__index = envelop

function envelop:reset()
	self.t = 0
	self.level_o = self.val
end

function envelop:next()
	if self.t < self.size then
		self.val = sfx.envelope(self.t, self.deltas, self.levels, self.level_0)
		self.t = self.t + 1 / SR
	end
	return self.val
end

function sfx.Env(deltas, levels)
	local size = 0
	for _, v in ipairs(deltas) do
		size = size + v
	end
	local s = {
		deltas = deltas;
		levels = levels;
		t = 0;
		size = size;
		val = 0;
		level_0 = 0;
	}
	setmetatable(s, envelop)
	return s
end
local delay = {}
delay.__index = delay

function delay:next(x)
	local y
	y, self.pos = sfx.delay(self.buf, self.pos, x, self.level, self.fb)
	return y
end

function sfx.Delay(size, level, fb)
	fb = fb or 0.5
	local s = {
		buf = {};
		level = level;
		fb = fb or 0.5;
		pos = 1;
	}
	for i = 1, sfx.sec(size) do
		s.buf[i] = 0
	end
	setmetatable(s, delay)
	return s
end

local function update(self, freq, vol)
	if freq then
		self.freq = freq
		self.env:reset()
	end
	if vol then
		self.vol = vol / 255
	end
end

local squarev = {
	update = update;
}
squarev.__index = squarev

function squarev:next()
	local a = sfx.square(self.ph1:next(self.freq) + 2 * math.sin(self.ph2:next(4)))
	return self.vol * a * self.env:next()
end

function sfx.SquareVoice()
	local s = {
		ph1 = sfx.Phasor();
		ph2 = sfx.Phasor();
		freq = 0;
		vol = 0;
		env = sfx.Env({0.01, 0.5}, {1, 0});
	}
	setmetatable(s, squarev)
	return s
end

local sawv = {
	update = update;
}
sawv.__index = sawv

function sawv:next()
	local mod = 0.2 + math.abs(1 + math.sin(self.ph2:next(1))) * 0.3
	local a = sfx.saw(self.ph1:next(self.freq) + 2 * math.sin(self.ph3:next(4)), mod)
	return self.dly:next(self.vol * a * self.env:next())
end

function sfx.SawVoice()
	local s = {
		ph1 = sfx.Phasor();
		ph2 = sfx.Phasor();
		ph3 = sfx.Phasor();
		dly = sfx.Delay(0.5, 0.5);
		freq = 0;
		vol = 0;
		env = sfx.Env({0.01, 0.1}, {1, 0.5})
	}
	setmetatable(s, sawv)
	return s
end

local lfsr = {}
lfsr.__index = lfsr

function lfsr:next(freq)
	local y = bit.bans(self.state, 1)
	self.phase = self.phase + 2 * freq * (1 / SR)
	if self.phase > 1 then
		self.phase = self.phase - 1
		self.state = sfx.lfsr(self.state, self.bits, self.taps)
	end
	return 2 * y - 1
end

function sfx.LFSR(bits, taps)
	local s = {
		bits = bits;
		taps = taps;
		state = 1;
		phase = 0;
	}
	setmetatable(s, lfsr)
	return s
end

function sfx.play_song(voices, pans, tracks, tick)
	for _, row in ipairs(tracks) do
		for voice, ro in table.zip(voices, row) do
			voice:update(table.unpack(ro))
		end
		for i = 1, sfx.sec(tick or 1/8) do
			local left, right = 0, 0
			for voice, pan in table.zip(voices, pans) do
				local l, r = sfx.set_stereo(voice:next(), pan)
				left = left + l
				right = right + r
			end
			coroutine.yield(left, right)
		end
	end
end
--[==[
	local voices = {
		sfx.SquareVoice(),
		sfx.SawVoice(),
		sfx.SquareVoice(),
	}
	print(voices[1], voices[2], voices[3])
	local pans = { -1, 0, 1 };
	local song = [[
C-3 80 | E-4 FF | C-5 50
... .. | ... .. | D-5 45
... .. | ... .. | C-5 40
E-3 .. | ... .. | D-5 35
... .. | ... .. | C-5 30
... .. | ... .. | D-5 25
G-3 .. | D-4 A0 | C-5 20
... .. | ... .. | D-5 15
... .. | ... .. | C-5 10
C-3 .. | C-4 FF | D-5 50
... .. | ... .. | C-5 45
... .. | ... .. | D-5 40
E-3 .. | G-3 FF | C-5 35
... .. | ... .. | D-5 30
... .. | ... .. | C-5 25
G-3 .. | ... .. | D-5 20
... .. | ... .. | C-5 15
... .. | ... .. | D-5 10
C-3 .. | A-3 A0 | C-5 50
... .. | ... .. | D-5 45
... .. | ... .. | C-5 40
E-3 .. | ... .. | D-5 35
... .. | ... .. | C-5 30
... .. | ... .. | D-5 25
G-3 .. | ... .. | C-5 20
... .. | ... .. | D-5 15
... .. | ... .. | C-5 10
C-3 .. | C-4 FF | D-5 50
... .. | ... .. | C-5 45
... .. | ... .. | D-5 40
E-3 .. | ... .. | C-5 35
... .. | ... .. | C-5 30
... .. | ... .. | D-5 25
G-3 .. | ... .. | C-5 20
]]
	sfx.play_song(voices, pans, sfx.parse_song(song))
]==]
return sfx
