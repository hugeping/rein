-- https://github.com/true-grue/libzvuk/blob/main/libzvuk.ipynb
-- Adopted by Peter Kosyh, original code by Peter Sovietov
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

function sfx.sin(freq)
  return math.sin(freq)
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
    x = bit.bxor(x, bit.rshift(state, t))
  end
  return bit.bor(bit.rshift(state, 1),
           (bit.lshift(bit.band(bit.bnot(x), 1), bits - 1)))
end

function sfx.envelope(t, deltas, levels, level_0, func)
  level_0 = level_0 or 0
  func = func or sfx.mix
  local t_0 = 0
  local dt, level
  for i = 1, #deltas do
    dt, level = deltas[i], levels[i]
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

local Phasor = {}
Phasor.__index = Phasor
function sfx.Phasor()
  local s = {
    phase = 0;
  }
  setmetatable(s, Phasor)
  return s
end

function Phasor:reset()
  self.phase = 0
end

function Phasor:next(freq)
  local p = self.phase
  self.phase = (self.phase + (2 * PI / SR) * freq) % (4 * PI)
  return p
end

local Env = {}
Env.__index = Env

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
  setmetatable(s, Env)
  return s
end

function Env:reset()
  self.t = 0
  self.level_0 = self.val
end

function Env:next()
  if self.t < self.size then
    self.val = sfx.envelope(self.t, self.deltas, self.levels, self.level_0)
    self.t = self.t + 1 / SR
  end
  return self.val
end

local Delay = {}
Delay.__index = Delay

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
  setmetatable(s, Delay)
  return s
end

function Delay:next(x)
  local y
  y, self.pos = sfx.delay(self.buf, self.pos, x, self.level, self.fb)
  return y
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

local SquareVoice = {
  update = update;
}

SquareVoice.__index = SquareVoice

function sfx.SquareVoice()
  local s = {
    ph1 = sfx.Phasor();
    ph2 = sfx.Phasor();
    freq = 0;
    vol = 0;
    env = sfx.Env({0.01, 0.5}, {1, 0});
  }
  setmetatable(s, SquareVoice)
  return s
end

function SquareVoice:next()
  local a = sfx.square(self.ph1:next(self.freq) + 2 * math.sin(self.ph2:next(4)))
  return self.vol * a * self.env:next()
end

local SawVoice = {
  update = update;
}
SawVoice.__index = SawVoice

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
  setmetatable(s, SawVoice)
  return s
end

function SawVoice:next()
  local mod = 0.2 + math.abs(1 + math.sin(self.ph2:next(1))) * 0.3
  local a = sfx.saw(self.ph1:next(self.freq) + 2 * math.sin(self.ph3:next(4)), mod)
  return self.dly:next(self.vol * a * self.env:next())
end

local LFSR = {}
LFSR.__index = LFSR

function sfx.LFSR(bits, taps)
  local s = {
    bits = bits;
    taps = taps;
    state = 1;
    phase = 0;
  }
  setmetatable(s, LFSR)
  return s
end

function LFSR:next(freq)
  local y = bit.band(self.state, 1)
  self.phase = self.phase + 2 * freq * (1 / SR)
  if self.phase > 1 then
    self.phase = self.phase - 1
    self.state = sfx.lfsr(self.state, self.bits, self.taps)
  end
  return 2 * y - 1
end

local BDVoice = {}
BDVoice.__index = BDVoice

function sfx.BDVoice()
  local s = {
    ph1 = sfx.Phasor();
    ph2 = sfx.Phasor();
    e1 = sfx.Env({0.001, 0.01, 0.2}, {400, 20, 0});
    env = sfx.Env({0.001, 0.15}, {1, 0});
    e3 = sfx.Env({0.001, 0.25}, {120, 0});
    vol = 0;
  }
  setmetatable(s, BDVoice)
  return s
end

function BDVoice:update(freq, vol)
  if freq then
    self.env:reset()
    self.e1:reset()
    self.e3:reset()
  end
  if vol then
    self.vol = vol / 255
  end
end

function BDVoice:next()
  local y = math.sin(self.ph2:next(self.e3:next())) * 1.5 + sfx.dsf(self.ph1:next(self.e1:next()), 4, 0.5)
  return y * self.env:next() * 0.3 * self.vol
end

local SnareVoice = {}
SnareVoice.__index = SnareVoice

function sfx.SnareVoice()
  local s = {
    ph1 = sfx.Phasor();
    ph2 = sfx.Phasor();
    n1 = sfx.LFSR(26, {0, 5, 10, 13, 15, 20, 27});
    env = sfx.Env({0.001, 0.15}, {1, 0});
    e2 = sfx.Env({0.001, 0.1}, {5000, 3000});
    e4 = sfx.Env({0.001, 0.15}, {200, 100});
    vol = 0;
  }
  setmetatable(s, SnareVoice)
  return s
end

function SnareVoice:update(freq, vol)
  if freq then
    self.env:reset()
    self.e2:reset()
    self.e4:reset()
  end
  if vol then
    self.vol = vol / 255
  end
end

function SnareVoice:next()
  local a = self.env:next()
  local y = math.sin(self.ph1:next(self.e4:next())) * a * 0.75
  y = y + self.n1:next(self.e2:next()) * math.sin(self.ph2:next(7500)) * a
  return y * a * 0.6 * self.vol
end

local EmptyVoice = {
}
EmptyVoice.__index = EmptyVoice

function sfx.EmptyVoice()
  local s = {
  }
  setmetatable(s, EmptyVoice)
  return s
end

function EmptyVoice:next()
  return 0
end

function EmptyVoice:update()
end

function sfx.play_song_once(chans, pans, tracks, temp)
  for _, row in ipairs(tracks) do
    for i, c in ipairs(chans) do
      local freq, vol = row[i][1], row[i][2]
      if freq then
        synth.change(c, 0, synth.NOTE_ON, freq)
        synth.change(c, 0, synth.VOLUME, 1)
      end
      if vol then
        synth.set(c, true, vol/255, pans[i])
      end
    end
    for i = 1, temp do
      coroutine.yield()
    end
  end
end

function sfx.play_song(chans, pans, tracks, temp, nr)
  nr = nr or 1
  while nr == -1 or nr > 0 do
    if nr ~= -1 then nr = nr - 1 end
    sfx.play_song_once(chans, pans, tracks, temp)
  end
end

return sfx
