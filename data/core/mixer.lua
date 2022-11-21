local dump = require "dump"
local sfx = require "sfx"
require "std"
local THREADED = true

local mixer = {
  vol = 0.5;
  req = { };
  ack = { };
  chans = { };
  freq = 1/100;
  hz = 44100;
}
mixer.tick = mixer.hz * mixer.freq

local test = coroutine.create(function()
local song = [[
C-3 A0 | ... .. | C-4 .. | C-3 64
... .. | ... .. | G-3 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | D#4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | F-4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | ... .. | G-4 .. | ... ..
... .. | C-3 80 | F-4 45 | ... ..
C-3 A0 | ... .. | C-4 .. | ... ..
... .. | ... .. | G-4 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | D#4 .. | D-3 64
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | D-4 .. | D#3 64
... .. | ... .. | D#4 45 | ... ..
C-3 A0 | ... .. | G-3 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | C-4 .. | G#2 64
... .. | ... .. | G-3 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 A0 | ... .. | D#4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | F-4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | ... .. | G-4 .. | ... ..
... .. | C-3 80 | F-4 45 | ... ..
C-3 a0 | ... .. | C-4 .. | ... ..
... .. | ... .. | G-4 45 | ... ..
C-3 80 | ... .. | C-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | C-4 45 | ... ..
C-3 A0 | ... .. | D-4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 a0 | ... .. | D#4 .. | ... ..
... .. | C-3 80 | D-4 45 | ... ..
C-3 80 | ... .. | D#4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | C-3 80 | D-4 .. | ... ..
... .. | ... .. | D#4 45 | ... ..
... .. | ... .. | G-3 .. | ... ..
... .. | ... .. | D-4 45 | ... ..
]]
  synth.push(1, "test_square")
  synth.push(2, "test_square")
  synth.push(3, "test_square")
  synth.push(4, "test_square")
  synth.set(1, true, 1)
  synth.set(2, true, 1)
  synth.set(3, true, 1)
  synth.set(4, true, 1)
  local song = sfx.parse_song(song)
  sfx.play_song({1, 2, 3, 4 }, { 0, 0, -0.75, 0.75 }, song, 16)
end)

function mixer.change()
-- TODO
--  local r, e = coroutine.resume(test)
--  if not r then print(e) end
end

function mixer.proc(tick)
  local rc
  repeat
    rc = synth.mix(tick, mixer.vol)
    if rc == 0 then sys.sleep(mixer.freq*2) end
    tick = tick - rc
  until tick == 0
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
    local rd, _ = thread:poll(0)
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

function mixer.thread()
  print "mixer start"
  local r, v, a
  while true do
    r, v, a = mixer.getreq()
    if r == 'quit' then -- stop thread
      mixer.answer()
      break
    elseif r == 'volume' then -- set/get master volume
      local oval = mixer.vol
      mixer.vol = v or oval
      mixer.answer(oval)
    end
    mixer.change()
    mixer.proc(mixer.tick) -- write to audio!
  end
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
  synth.stop()
  if mixer.thr then
    mixer.clireq 'quit'
  end
  core.stop(mixer.co)
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
