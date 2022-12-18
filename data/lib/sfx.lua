require "std"

local sfx = {
  voices_bank = {},
  sfx_bank = {},
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
  if name:find("[=]+") then
    return 0
  end
  local n, o = name:sub(1, 2):lower(), tonumber(name:sub(3))
  return sfx.get_midi_note(NOTES[n] + 12 * (o + 2))
end

function sfx.parse_cmd(cmd, mus)
  cmd = cmd:split()
  local ret = {}
  ret.fn = cmd[1]:sub(2):strip()
  if cmd[1] == '@play' then
    local song = sfx.sfx_bank[cmd[2]]
    if not song then
      return false, "No such sfx: "..tostring(cmd[2])
    end
    if song.tracks > mus.tracks then mus.tracks = song.tracks end
    ret.args = { cmd[2] }
    return ret
  elseif cmd[1] == '@temp' then
    ret.args = { tonumber(cmd[2]) or 1 }
    return ret
  elseif cmd[1] == '@push' then
    ret.args = { tonumber(cmd[2]) or -1 }
    return ret
  elseif cmd[1] == '@pop' then
    ret.args = { }
    return ret
  end
  local chan = tonumber(cmd[2])
  if not chan then
    return false, "No channel arg in command: "..tostring(cmd[1])
  end
  ret.chan = chan
  if cmd[1] == '@voice' then
    local voice = cmd[3]
    ret.args = { voice }
  elseif cmd[1] == '@pan' then
    local pan = tonumber(cmd[3]) or 0
    ret.args = { pan }
  elseif cmd[1] == '@volume' then
    ret.args = { tonumber(cmd[3]) or 0 }
  else
    return false, "Wrong command: "..tostring(cmd[1])
  end
  return ret
end

function sfx.parse_data(text, mus)
  local cols = text:split(" ")
  local data = { not cols[1]:startswith "." and sfx.get_note(cols[1])
             or false }
  for i = 2, #cols do
    table.insert(data, not cols[i]:startswith "." and
           tonumber(cols[i], 16) or false)
  end
  return data
end

function sfx.parse_row(text, mus)
  local ret = {}
  local r, e
  if text:startswith("@") then -- directive
    r, e = sfx.parse_cmd(text, mus)
    if not r then
      return r, e
    end
    ret.cmd = r
    return ret
  end
  for _, v in ipairs(text:split("|")) do
    v, e = sfx.parse_data(v:strip(), mus)
    if not v then
      return v, e
    end
    table.insert(ret, v)
  end
  return ret
end

function sfx.parse_song(text)
  if not tostring(text):find("\n") then
    local song = sfx.sfx_bank[text]
    if not song then
      return false, "No such sfx:"..tostring(text)
    end
    return song
  end
  local ret = { tracks = 0 }
  text = text:strip()
  for row in text:lines() do
    local r, e = sfx.parse_row(row:strip(), ret)
    if not r then
      return r, e
    end
    table.insert(ret, r)
    ret.tracks = #r > ret.tracks and #r or ret.tracks
  end
  if ret.tracks == 0 then
    return false, "Wrong sfx format"
  end
  return ret
end

function sfx.new(nam, song)
  local snd = song
  local e
  if type(song) == 'string' then
    snd, e = sfx.parse_song(song)
    if not snd then return snd, e end
  end
  sfx.sfx_bank[nam] = snd
  return true
end

local function chan_par(chans, ch)
  ch = ch or 1
  if ch ~= -1 then
    return { chans[ch] or 0 }
  end
  return chans
end

sfx.proc = {}

function sfx.proc.push(chans, mus, nr)
  if not mus.stack then mus.stack = {} end
  table.insert(mus.stack, 1, { mus.row + 1, nr } )
end

function sfx.proc.pop(chans, mus)
  local r = mus.stack and mus.stack[1]
  if not r or r[2] == 0 then return end
  mus.row = r[1]
  if r[2] and r[2] > 0 then r[2] = r[2] - 1 end
end

function sfx.proc.play(chans, mus, song)
  sfx.play_song(chans, sfx.sfx_bank[song], mus.temp)
end

function sfx.proc.voice(chans, mus,...)
  sfx.apply(...)
end

function sfx.proc.pan(chans, mus,...)
  synth.pan(...)
end

function sfx.proc.volume(chans, mus, ...)
  synth.vol(...)
end

function sfx.proc.temp(chans, mus, temp)
  mus.temp = temp
end

function sfx.proc_cmd(chans, mus, cmd)
  if not cmd then return end
  if not cmd.chan then
    sfx.proc[cmd.fn](chans, mus, table.unpack(cmd.args))
    return
  end
  for _, c in ipairs(chan_par(chans, cmd.chan)) do
    sfx.proc[cmd.fn](chans, mus, c, table.unpack(cmd.args))
  end
end

function sfx.play_song_once(chans, tracks, temp)
  tracks.temp = temp
  local row
  tracks.row = 1
  while tracks.row <= #tracks do
    row = tracks[tracks.row]
    sfx.proc_cmd(chans, tracks, row.cmd)
    row = tracks[tracks.row]
    for i, r in ipairs(row) do
      local freq, vol = r[1], r[2]
      if freq then
        if freq == 0 then
          synth.chan_change(chans[i], synth.NOTE_OFF, 0)
        else
          synth.chan_change(chans[i], synth.NOTE_ON, freq)
        end
      end
      if vol then
        synth.change(chans[i], 0, synth.VOLUME, vol/255)
      end
    end
    if #row > 0 then
      for i = 1, tracks.temp do
        coroutine.yield()
      end
    end
    tracks.row = tracks.row + 1
  end
end

function sfx.play_song(chans, tracks, temp, nr)
  nr = nr or 1
  temp = temp or 1
  while nr == -1 or nr > 0 do
    if nr ~= -1 then nr = nr - 1 end
    sfx.play_song_once(chans, tracks, temp)
  end
end

local function par_choice(...)
  return { choice = {...} }
end

local boxes = {
  { nam = 'synth',
    { "volume", synth.VOLUME, def = 0.5 },
    { 'type', synth.TYPE,
      def = 'sin',
      choice = { 'sin', 'saw', 'square', 'dsf',
        'dsf2', 'pwm',
        'noise', 'band_noise', 'sin_band_noise',
      },
      vals = { synth.OSC_SIN, synth.OSC_SAW, synth.OSC_SQUARE, synth.OSC_DSF,
        synth.OSC_DSF2, synth.OSC_PWM,
        synth.OSC_NOISE, synth.OSC_BAND_NOISE, synth.OSC_SIN_BAND_NOISE
      },
    },
    { 'freq', synth.FREQ, def = 0 },
    { 'fmul', synth.FMUL, def = 1 },
    { 'amp', synth.AMP, def = 1.0 },
    { 'width', synth.WIDTH, def = 0.5 },
    { 'offset', synth.OFFSET, def = 1 },
    { 'set_lin', synth.SET_LIN, def = 1 },
    { 'freq2', synth.FREQ2, def = 0 },
    { 'attack', synth.ATTACK, def = 0.01 },
    { 'decay', synth.DECAY, def = 0.1 },
    { 'sustain', synth.SUSTAIN, def = 0.5 },
    { 'release', synth.RELEASE, def = 0.3 },
    { 'set_sustain', synth.SET_SUSTAIN, def = 0 },
    { 'set_glide', synth.SET_GLIDE, def = 0 },
    { 'glide_rate', synth.GLIDE_RATE, def = 0 },
    { 'remap', synth.REMAP,
      array = {
        'freq', 'fmul', 'amp', 'width', 'offset', 'set_lin', 'freq2',
      },
      array_vals = {
        synth.OSC_FREQ, synth.OSC_FMUL, synth.OSC_AMP,
        synth.OSC_WIDTH, synth.OSC_OFFSET,
        synth.OSC_SET_LIN, synth.OSC_FREQ2
      },
      def = 'freq',
      choice = {
        'freq', 'fmul', 'amp', 'width', 'offset', 'set_lin', 'freq2'
      },
      vals = {
        synth.OSC_FREQ, synth.OSC_FMUL, synth.OSC_AMP,
        synth.OSC_WIDTH, synth.OSC_OFFSET,
        synth.OSC_SET_LIN, synth.OSC_FREQ2
      },
    },
    { 'lfo_type', synth.LFO_TYPE,
      array = { 0, 1, 2, 3 },
      def = 'zero',
      choice = { 'zero', 'sin', 'saw', 'square', 'triangle', 'seq' },
      vals = { synth.LFO_ZERO, synth.LFO_SIN, synth.LFO_SAW,
        synth.LFO_SQUARE, synth.LFO_TRIANGLE, synth.LFO_SEQ },
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
    { 'lfo_set_loop', synth.LFO_SET_LOOP,
      array = { 0, 1, 2, 3 },
      def = 1,
      choice = { 0, 1 },
    },
    { 'lfo_set_reset', synth.LFO_SET_RESET,
      array = { 0, 1, 2, 3 },
      choice = { 0, 1 },
      def = 1
    },
    { 'lfo_assign', synth.LFO_ASSIGN,
      array = { 0, 1, 2, 3 },
      choice = {
        'freq', 'fmul', 'amp', 'width', 'offset', 'set_lin', 'freq2'
      },
      def = 'freq',
      vals = { synth.OSC_FREQ, synth.OSC_FMUL, synth.OSC_AMP,
        synth.OSC_WIDTH, synth.OSC_OFFSET,
        synth.OSC_SET_LIN, synth.OSC_FREQ2 },
    },
    { 'lfo_seq_pos', synth.LFO_SEQ_POS,
      array = { 0, 1, 2, 3 },
      def = 0, min = 0, max = 127,
    },
    { 'lfo_seq_val', synth.LFO_SEQ_VAL,
      array = { 0, 1, 2, 3 },
      def = 0,
    },
    { 'lfo_seq_size', synth.LFO_SEQ_SIZE,
      array = { 0, 1, 2, 3 },
      def = 0, min = 0, max = 129,
    },
    { 'lfo_set_lin_seq', synth.LFO_SET_LIN_SEQ,
      array = { 0, 1, 2, 3 },
      choice = { 0, 1 },
      def = 0
    },
  },
  { nam = 'dist',
    { "volume", synth.VOLUME, def = 0.5 },
    { "gain", synth.GAIN, def = 0.5 },
  },
  { nam = 'delay',
    { 'volume', synth.VOLUME,  def = 0.5 },
    { 'time', synth.TIME, max = 1, min = 0, def = 1},
    { 'level', synth.LEVEL, def = 0.5 },
    { 'feedback', synth.FEEDBACK, def = 0.5 },
  },
  { nam = 'filter' ,
    { 'volume', synth.VOLUME,  def = 0.5 },
    { 'type', synth.TYPE, def = 'lowpass',
      choice = { 'lowpass', 'highpass' },
      vals = { synth.LOWPASS, synth.HIGHPASS },
    },
    { 'width', synth.WIDTH, def = 0.5 },
  }
}

function sfx.box_info(nam)
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

local function par_array(p, par)
  for idx, v in ipairs(p.array) do
    if v == par or v == tonumber(par) then
      if p.array_vals then
        return p.array_vals[idx]
      end
      return v
    end
  end
end

local function elem_help(par)
  local help = ''
  for _, v in ipairs(par.array) do
    if help ~= '' then help = help .. ',' end
    help = help .. tostring(v)
  end
  return help
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

function sfx.compile_par(nam, l)
  local v = sfx.box_info(nam)
  local a, p
  local cmd = {}
  a = l:split("#", 1)
  a = a[1] and a[1]:split()
  if a and a[1] and not a[1]:empty() then
    p = par_lookup(v, a[1])
    if not p then
      return false, string.format("Param:%s", a[1])
    end
    if not p[2] then
      return false, string.format("Internal error:%s", l)
    end
    table.insert(cmd, p[2])
    if p.array then
      local elem = par_array(p, a[2])
      if not elem then
        return false, string.format("Element:%s\nHelp:%s", a[2], elem_help(p))
      end
      table.insert(cmd, elem)
      table.remove(a, 2)
    end
    local val = par_value(p, a[2])
    if not val then
      return false, string.format("Value:%s\nHelp:%s", a[2], par_help(p))
    end
    table.insert(cmd, val)
  end
  return cmd
end

function sfx.compile_box(nam, text)
  local line = 0
  local res = {}
  local cmd, e
  for l in text:lines() do
    line = line + 1
    cmd, e = sfx.compile_par(nam, l)
    if not cmd then
      return false, e, line
    end
    if #cmd > 0 then
      table.insert(res, cmd)
    end
  end
  return res
end

function sfx.parse_voices(text)
  local box
  local line = 0
  local res = {}
  local cmd, e, a
  local voice
  local nr = 0
  if not text:find("\n") then -- filename?
    text, e = io.file(text)
    if not text then
      return text, e
    end
  end
  for l in text:lines() do
    l = l:strip()
    line = line + 1
    a = l:split("#", 1)
    a = a[1] and a[1]:split() or {}
    if a[1] == 'voice' then
      box = nil
      nr = nr + 1
      voice = { nam = a[2] or tonumber(nr) }
      table.insert(res, voice)
    elseif not voice and a[1] and not a[1]:empty() then
      return false, "No voice declaration", line
    elseif a[1] == 'box' then
      if not sfx.box_info(a[2]) then
        return false, string.format("Wrong box name: %s", a[2]), line
      end
      box = { nam = a[2], conf = '' }
      table.insert(voice, box)
    elseif box then
      box.conf = box.conf .. l .. '\n'
      cmd, e = sfx.compile_par(box.nam, l)
      if not cmd then
        return false, e, line
      end
      if #cmd > 0 then
        table.insert(box, cmd)
      end
    elseif a[1] and not a[1]:empty() then
      return false, "No box declaration", line
    end
  end
  return res
end

function sfx.voices(voices)
  local e
  if type(voices) == 'string' then
    voices, e = sfx.parse_voices(voices)
    if not voices then return false, e end
  end
  for k, v in ipairs(voices) do
    sfx.voices_bank[v.nam or k] = v
  end
  return true
end

function sfx.apply(chan, voice)
  local vo = sfx.voices_bank[voice]
  if not vo then
    error("Unknown voice: "..tostring(voice), 2)
  end
  synth.drop(chan)
  for i, b in ipairs(vo) do
    synth.push(chan, b.nam)
    for _, p in ipairs(b) do
      synth.change(chan, -1, table.unpack(p))
    end
  end
end

function sfx.box_defs(nam)
  local v = sfx.box_info(nam)
  local txt = string.format("# %s\n", nam)
  for _, p in ipairs(v) do
    if p.comment then txt = txt .. '# ' end
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
