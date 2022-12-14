local dump = require "dump"
local sfx = require "sfx"
require "std"
local THREADED = not not thread

local mixer = {
  id = 0;
  reserve = 0;
  ids = {};
  vol = 0.5;
  req = { };
  ack = { };
  fn = { };
  chans = { size = 32 };
  freq = 1/100;
  hz = 44100;
}
mixer.tick = mixer.hz * mixer.freq

function mixer.get_channels(nr)
  local free = {}
  for i = mixer.reserve + 1, mixer.chans.size do
    if not mixer.chans[i] then
      table.insert(free, i)
      if #free >= nr then break end
    end
  end
  if #free < nr then
    return false
  end
  for _, c in ipairs(free) do
    mixer.chans[c] = true
  end
  return free
end

function mixer.apply_voice(chan, voice)
  sfx.apply_voice(chan, voice)
end

function mixer.req_nextid()
  while mixer.ids[mixer.id] do
    mixer.id = (mixer.id + 1) % 0xffff
  end
end


function mixer.free_channels(chans)
  if not chans then
    for i=mixer.reserve + 1, mixer.chans.size do
      mixer.chans[i] = false
    end
    return
  end
  for _, c in ipairs(chans) do
    mixer.chans[c] = false
  end
end

function mixer.release(r)
  mixer.free_channels(r.chans)
  mixer.ids[r.id] = nil
end

function mixer.change()
  local r, e
  for i, v in ipairs(mixer.fn) do
    if coroutine.status(v.fn) ~= 'dead' then
      r, e = coroutine.resume(v.fn, table.unpack(v.args))
      if not r then error(e) end
    else
      mixer.fn[i].dead = true
    end
  end
  local i = 1
  while i <= #mixer.fn do -- clean dead coroutines and free chans
    if mixer.fn[i].dead then
      r = table.remove(mixer.fn, i)
      mixer.release(r)
    else
      i = i + 1
    end
  end
end

function mixer.proc(tick)
  local rc
  repeat
    rc = synth.mix(tick, mixer.vol)
    if rc == 0 then coroutine.yield() end -- sys.sleep(mixer.freq*2) end
    tick = tick - rc
  until tick == 0
end

function mixer.req_play(text, temp, nr)
  local song, e = sfx.parse_song(text)
  if not song then
    return false, e
  end
  local chans = mixer.get_channels(song.tracks)
  if not chans then
    return false, "No free channels"
  end
  local f, e = coroutine.create(sfx.play_song)
  if not f then
    error(e)
  end
  mixer.req_nextid()
  local r = { id = mixer.id, fn = f, chans = chans,
    args = { chans, song, temp or 1, nr or 1 } }
  table.insert(mixer.fn, r)
  mixer.ids[mixer.id] = r
  return mixer.id
end

function mixer.req_voices(vo)
  return sfx.voices(vo)
end

function mixer.req_new(nam, snd)
  return sfx.new(nam, snd)
end

function mixer.req_reserve(nr)
  mixer.reserve = nr or 0
  return true
end

function mixer.getreq()
  if not mixer.thr then
    if not mixer.req then
      coroutine.yield()
    end
    local r =  mixer.req or {}
    mixer.req = false
    return table.unpack(r)
  else
    local rd, _ = thread:poll(mixer.freq * 2)
    if rd then
      return thread:read()
    end
  end
end

function mixer.answer(...)
  if not mixer.thr then
    mixer.ack = { ... }
    coroutine.yield()
  else
    thread:write(...)
  end
end

function mixer.reset()
  mixer.fn = {}
  mixer.ids = {}
end

mixer.sched = coroutine.create(function()
  while true do
    mixer.change()
    mixer.proc(mixer.tick) -- write to audio!
  end
end)

function mixer.thread()
  print "mixer start"
  local r, v, a, b, c
  mixer.reset()
  while true do
    r, v, a = mixer.getreq()
    if r == 'quit' then -- stop thread
      mixer.answer()
      break
    elseif r == 'volume' then -- set/get master volume
      local oval = mixer.vol
      mixer.vol = v or oval
      mixer.answer(oval)
    elseif r == 'play' then
      mixer.answer(mixer.req_play(table.unpack(v)))
    elseif r == 'new' then
      mixer.answer(mixer.req_new(v, a))
    elseif r == 'reserve' then
      mixer.answer(mixer.req_reserve(v))
    elseif r == 'voices' then
      mixer.answer(mixer.req_voices(v))
    end
    r, v = coroutine.resume(mixer.sched)
    if not r then
      error(v)
    end
  end
  mixer.free_channels()
  synth.stop()
  print "mixer finish"
end

----------------------------- Client side -------------------------------
function mixer.coroutine()
  if not mixer.thr then
    mixer.thread()
  else
    while mixer.running do
      local e = mixer.thr:err() -- force show peer end error msg
      if e then
        mixer.running = false
        error(e)
      end
      coroutine.yield()
    end
  end
end

function mixer.clireq(...)
  if not mixer.thr then
    mixer.req = { ... }
    coroutine.yield()
    local ack = mixer.ack
    mixer.ack = {}
    return table.unpack(ack)
  else
    mixer.thr:write(...)
    return mixer.thr:read()
  end
end

function mixer.volume(vol)
  return mixer.clireq("volume", vol)
end

function mixer.stop()
  if not mixer.running then return end
  mixer.running = false
  if mixer.thr then
    mixer.clireq 'quit'
  end
  core.stop(mixer.co)
end

function mixer.play(...)
  return mixer.clireq("play", {...})
end

function mixer.voices(text)
  local r, e = sfx.parse_voices(text)
  if not r then
    return r, e
  end
  return mixer.clireq("voices", r)
end

function mixer.new(nam, text)
  local r, e = sfx.parse_song(text)
  if not r then
    return r, e
  end
  return mixer.clireq("new", nam, r)
end

function mixer.reserve(nr)
  return mixer.clireq("reserve", nr)
end

function mixer.init()
  local t, r
  if mixer.running then return end
  mixer.running = true
  if THREADED then
    t, e = thread.start(function()
      local mixer = require "mixer"
      mixer.thr = thread
      mixer.thread()
    end)
  end
  if not t then
    print("Audio: coroutine mode")
  end
  mixer.thr = t
  mixer.co = core.go(mixer.coroutine)
end

return mixer
