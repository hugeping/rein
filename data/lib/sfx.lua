require "std"
local sfx = {
}

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

function sfx.play_song_once(chans, pans, tracks, temp)
  for i, c in ipairs(chans) do
    synth.on(c, true)
    synth.pan(c, pans[i])
    synth.vol(c, 0.5)
  end
  for _, row in ipairs(tracks) do
    for i, c in ipairs(chans) do
      local freq, vol = row[i][1], row[i][2]
      if freq then
        synth.change(c, 0, synth.NOTE_ON, freq)
      end
      if vol then
        synth.change(c, 0, synth.VOLUME, vol/255)
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

local function par_choice(...)
  return { choice = {...} }
end

local boxes = {
  { nam = 'synth',
    { "volume", synth.VOLUME, def = 0 },
    { 'mode', synth.MODE,
      def = 'sin',
      choice = { 'sin', 'saw', 'square', 'dsf',
        'dsf2', 'pwm', 'sin_noise', 'noise8' },
      vals = { synth.OSC_SIN, synth.OSC_SAW, synth.OSC_SQUARE, synth.OSC_DSF,
        synth.OSC_DSF2, synth.OSC_PWM, synth.OSC_SIN_NOISE, synth.OSC_NOISE8 },
    },
    { 'width', synth.WIDTH, def = 0.5 },
    { 'attack', synth.ATTACK, def = 0.01 },
    { 'decay', synth.DECAY, def = 0.1 },
    { 'sustain', synth.SUSTAIN, def = 0.5 },
    { 'release', synth.RELEASE, def = 0.3 },
    { 'sustain_on', synth.SUSTAIN_ON, def = 0 },
    { 'offset', synth.OFFSET, def = 0.5 },
    { 'amp', synth.AMP, def = 1.0 },
    { 'glide_on', synth.GLIDE_ON, def = 0 },
    { 'freq_mul', synth.FREQ_MUL, def = 1 },
--    { 'glide_off', synth.GLIDE_OFF, choice = { 0, 1}, def = 0 },
    { 'lfo_func', synth.LFO_FUNC,
      array = { 0, 1, 2, 3 },
      def = 'none',
      choice = { 'none', 'sin', 'saw', 'square', 'triangle' },
      vals = { synth.LFO_NONE, synth.LFO_SIN, synth.LFO_SAW,
        synth.LFO_SQUARE, synth.LFO_TRIANGLE },
    },
    { 'lfo_freq', synth.LFO_FREQ,
      array = { 0, 1, 2, 3 },
      def = 0,
    },
    { 'lfo_low', synth.LFO_LOW,
      array = { 0, 1, 2, 3 },
      def = 0,
    },
    { 'lfo_high', synth.LFO_HIGH,
      array = { 0, 1, 2, 3 },
      def = 0,
    },
    { 'lfo_loop', synth.LFO_LOOP,
      array = { 0, 1, 2, 3 },
      def = 1,
      choice = { 0, 1 },
    },
    { 'lfo_assign', synth.LFO_ASSIGN,
      array = { 0, 1, 2, 3 },
      choice = { 'amp', 'freq', 'freq_mul', 'width', 'offset' },
      def = 'amp',
      vals = { synth.LFO_TARGET_AMP, synth.LFO_TARGET_FREQ,
        synth.LFO_TARGET_FREQ_MUL, synth.LFO_TARGET_WIDTH,
        synth.LFO_TARGET_OFFSET },
    }
  },
  { nam = 'dist',
    { "volume", synth.VOLUME, def = 0 },
    { "gain", synth.GAIN, def = 0.5 },
  },
  { nam = 'delay',
    { 'volume', synth.VOLUME, { def = 0 } },
    { 'time', synth.TIME, { max = 1, min = 0, def = 1 } },
    { 'level', synth.LEVEL, { def = 0.5 } },
    { 'feedback', synth.FEEDBACK, { def = 0.5 } },
  },
--[[
{ nam = 'filter' ,
    { 'mode', synth.MODE, def = 1,
      choice = { 'lopass', 'highpass' },
      val = { synth.LOPASS, synth.HIGHPASS },
    },
    { 'width', synth.MODE, def = 0.5 },
  }
]]--
}

function sfx.getinfo(nam)
  for _, v in ipairs(boxes) do
    if v.nam == nam then
      return v
    end
  end
  error ("No such sfx box:".. tostring(nam), 2)
end

local function par_lookup(info, nam)
  for _, v in ipairs(info) do
    if v[1] == nam then
      return v
    end
  end
end

local function par_array(array, par)
  for _, v in ipairs(array) do
    if v == par then
      return v
    end
  end
end

local function par_help(par)
  local help = ''
  if par.choice then
    for idx, c in ipairs(par.choice) do
      if help ~= '' then help = help .. ',' end
      help = help .. tostring(c)
    end
    return help
  end
  if par.min and par.max then
    return string.format("%f <= number <= %f", par.min, par.max)
  end
  if par.min then
    return string.format("number >= %f", par.min)
  end
  if par.max then
    return string.format("number <= %f", par.max)
  end
  return "number"
end

local function par_value(par, val)
  if par.choice then
    for idx, c in ipairs(par.choice) do
      if c == val or c == tonumber(val) then
        return par.vals and par.vals[idx] or c
      end
    end
    return false
  end
  val = tonumber(val)
  if not val then
    return false
  end
  if par.min and val < par.min or par.max and val > par.max then
    return false
  end
  return val
end

function sfx.compile(nam, text)
  local v = sfx.getinfo(nam)
  local a, p
  local line = 0
  local res = {}
  for l in text:lines() do
    line = line + 1
    a = l:split("#", 1)
    a = a[1] and a[1]:split()
    if a and a[1] and not a[1]:empty() then
      p = par_lookup(v, a[1])
      if not p then
        return false, string.format("Param:%s", a[1]), line
      end
      local cmd = { p[2] }
      if p.array then
        local elem = par_array(p.array, tonumber(a[2]))
        if not elem then
          return false, string.format("Element:%s", a[2]), line
        end
        table.insert(cmd, elem)
        table.remove(a, 2)
      end
      local val = par_value(p, a[2])
      if not val then
        return false, string.format("Value:%s\nHelp:%s", a[2], par_help(p)), line
      end
      table.insert(cmd, val)
      table.insert(res, cmd)
    end
  end
  return res
end

function sfx.defs(nam)
  local v = sfx.getinfo(nam)
  local txt = string.format("# %s\n", nam)
  for _, p in ipairs(v) do
    if p.array then
      for _, a in ipairs(p.array) do
        txt = txt .. string.format("%s %s %s\n", p[1], a, p.def or 0)
        break -- only 1st
      end
    else
      txt = txt .. string.format("%s %s\n", p[1], p.def or 0)
    end
  end
  return txt
end

sfx.boxes = boxes

return sfx
