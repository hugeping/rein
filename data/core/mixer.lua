-- local dump = require "dump"
local sfx = require "sfx"
require "std"
local THREADED = not not thread

local mixer = {
  id = 0;
  res = 0;
  ids = {};
  vol = 0.5;
  srv = { };
  ack = { };
  fn = { };
  chans = { size = 32 };
  freq = 1/100;
  hz = 44100;
  req = {};
}
mixer.tick = mixer.hz * mixer.freq

function mixer.get_channels(nr)
  local free = {}
  for i = mixer.res + 1, mixer.chans.size do
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
    synth.on(c, true)
    synth.vol(c, 0.5)
  end
  return free
end

function mixer.apply(chan, voice)
  sfx.apply(chan, voice)
end

function mixer.req_nextid()
  while mixer.ids[mixer.id] do
    mixer.id = (mixer.id + 1) % 0xffff
  end
end

function mixer.free_channels(chans)
  if not chans then
    for i=mixer.res + 1, mixer.chans.size do
      mixer.chans[i] = false
    end
    return
  end
  for _, c in ipairs(chans) do
    mixer.chans[c] = false
    synth.drop(c)
    synth.on(c, false)
  end
end

function mixer.release(r)
  mixer.free_channels(r.chans)
  mixer.ids[r.id] = nil
end

function mixer.change()
  local r, e
  for i, v in ipairs(mixer.fn) do
    if coroutine.status(v.fn) ~= 'dead' and not v.dead then
      r, e = coroutine.resume(v.fn, table.unpack(v.args))
      if not r then error(e) end
      if v.fadeout then
        for _, c in ipairs(v.chans) do
          synth.mul_vol(c, v.fadeout)
        end
        v.fadeout = v.fadeout - v.fade_delta
        if v.fadeout <= 0 then
          mixer.fn[i].dead = true
        end
      end
    else
      mixer.fn[i].dead = true
    end
  end
  local i = 1
  while i <= #mixer.fn do -- clean dead coroutines and free chans
    if mixer.fn[i].dead and not mixer.fn[i].status then
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

function mixer.srv.play(text, nr)
  local song, e = sfx.parse_song(text)
  if not song then
    return false, e
  end
  local chans = mixer.get_channels(song.tracks)
  if not chans then
    return false, "No free channels"
  end
  local state, f
  f, e = coroutine.create(function(...)
    local r, err = sfx.play_song(...)
    if not r then
      state.status = err
    end
    return r, err
  end)
  if not f then
    error(e)
  end
  mixer.req_nextid()
  state = { id = mixer.id, fn = f, chans = chans,
    args = { chans, song, nr or 1 } }
  table.insert(mixer.fn, state)
  mixer.ids[mixer.id] = state
  return mixer.id
end

function mixer.srv.voices(vo)
  return sfx.voices(vo)
end

function mixer.srv.new(nam, snd)
  return sfx.new(nam, snd)
end

function mixer.srv.songs(songs)
  return sfx.songs(songs)
end

function mixer.srv.stop(id, fo)
  local r = mixer.ids[id]
  if not r then return false, "No such sfx" end
  if not fo or fo == 0 or r.dead then
    r.dead = true
    local e = r.status
    r.status = nil
    return true, e
  end
  r.fadeout = 1
  r.fade_delta = mixer.freq / fo
  return true
end

function mixer.srv.status(id)
  local r = mixer.ids[id]
  if not r then return false end
  if r.dead then
    local e = r.status
    r.status = nil
    return false, e or "Sfx is canceled"
  end
  return r.args[2].row or 1
end

function mixer.srv.reserve(nr)
  mixer.res = nr or 0
  return true
end

function mixer.srv.volume(v)
  local oval = mixer.vol
  mixer.vol = v or oval
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
  local r, v
  mixer.reset()
  while true do
    r, v = mixer.getreq()
    if r == 'quit' then -- stop thread
      mixer.answer()
      break
    elseif r and mixer.srv[r] then
      mixer.answer(mixer.srv[r](table.unpack(v)))
    elseif r then
      mixer.answer(false, "Unknown method")
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
  if core.nosound then vol = 0 end
  return mixer.clireq("volume", { vol })
end

function mixer.done()
  if not mixer.running then return end
  mixer.running = false
  if mixer.thr then
    mixer.clireq 'quit'
    mixer.thr:wait()
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
  return mixer.clireq("voices", { r })
end

function mixer.new(nam, text)
  local r, e = sfx.parse_song(text)
  if not r then
    return r, e
  end
  return mixer.clireq("new", { nam, r })
end

function mixer.songs(text)
  local r, e = sfx.parse_songs(text)
  if not r then
    return r, e
  end
  return mixer.clireq("songs", { r })
end

function mixer.reserve(nr)
  return mixer.clireq("reserve", { nr })
end

function mixer.stop(nr, fade)
  return mixer.clireq("stop", { nr, fade })
end

function mixer.status(nr)
  return mixer.clireq("status", { nr })
end

function mixer.init()
  local t
  if mixer.running then return end
  mixer.running = true
  if THREADED then
    t = thread.start(function()
      local mix = require "mixer"
      mix.thr = thread
      mix.thread()
    end)
  end
  if not t then
    print("Audio: coroutine mode")
  end
  mixer.thr = t
  mixer.co = core.go(mixer.coroutine)
  if core.nosound then mixer.volume(0) end
end

return mixer
