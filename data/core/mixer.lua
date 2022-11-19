local dump = require "dump"
require "std"
local THREADED = true
local CHUNK = 8192
local CHANNELS = 8
local DELAY = 1/30

local mixer = {
  vol = 0.5;
  req = { };
  ack = { };
  chans = { };
  buff = {
    channels = 2,
    head = 1,
    tail = 1,
    size = CHUNK,
    used = 0
  };
}

function mixer.fill()
  local size = #mixer.buff
  local b = mixer.buff
  local pos = b.tail
  for i = 1, b.size-b.used, b.channels do -- fill bufer
    local ll, rr = 0, 0
    local n = 0
    for k = 1, CHANNELS do
      local m = mixer.chans[k]
      local fn = m.fn
      if fn then
        local st, l, r = coroutine.resume(fn,
          (not m.run) and table.unpack(m.args))
        m.run = true
        r = r or l
        if not st or not l then
          mixer.chans[k].fn = false -- stop it
          if not st then
            error(l..'\n'..debug.traceback(fn))
          end
        else
          n = n + 1
          ll = ll + l
          if b.channels == 2 then
            rr = rr + r
          end
        end
      end
    end
    if n == 0 and i == 1 then -- nothing this iter
      return
    end
    b[pos] = ll * mixer.vol -- / n
    pos = (pos % b.size) + 1
    b.used = b.used + 1
    if b.channels == 2 then
      b[pos] = rr * mixer.vol -- / n
      pos = (pos % b.size) + 1
      b.used = b.used + 1
    end
  end
  b.tail = pos
end

function mixer.write_audio()
  local b = mixer.buff
  if b.used == 0 then
    return
  end
  local size = synth.change(0, 0, -1)
  local rc = (b.used / b.channels) > size and size or (b.used / b.channels)
  repeat
    rc = synth.mix(rc)
    for i = 1, rc do
      synth.change(0, 0, 0, b[b.head], b[b.head+1])
      b.head = ((b.head + 1) % b.size) + 1
      b.used = b.used - 2
      if b.used == 0 then break end
    end
  until b.used == 0 or rc == 0
end

function mixer.req_send(a)
  local m = mixer.chans[a.channel]
  if not m or not m.fn or a.id ~= m.id then
    return false
  end
  m.args = a
  m.send = true
  return true
end

function mixer.req_stop(a)
  local m = mixer.chans[a.channel]
  if not m or not m.fn or a.id ~= m.id then
    return false
  end
  m.fn = false
  return true
end

local req_id = 0
function mixer.req_new(fn, a)
  local f, e = coroutine.create(fn)
  if not f then
    error(e)
  end
  for i = 1, CHANNELS do
    if not mixer.chans[i].fn then
      req_id = (req_id % 65535) + 1
      mixer.chans[i] = { fn = f, time = sys.time(),
        args = a, id = req_id }
      return i, req_id
    end
  end
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
    local rd, _ = thread:poll(DELAY)
    local r, v, a
    if rd then
      r, v, a = thread:read()
    end
    if r == 'new' then
      v = dump.new(v) -- function
    end
    return r, v, a
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

function mixer.reqs()
  for k = 1, CHANNELS do -- make requests
    local m = mixer.chans[k]
    local fn = m.fn
    if m.send then
      mixer.answer(coroutine.resume(fn, table.unpack(m.args)))
      m.send = false
    end
  end
end

function mixer.thread()
  print "mixer start"
  synth.push(0, 'custom_stereo')
  synth.set(0, true, 1)
  for i = 1, CHANNELS do
    mixer.chans[i] = { }
  end
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
    elseif r == 'new' then -- new generator
      mixer.answer(mixer.req_new(v, a))
    elseif r == 'send' then -- send to generator
      if not mixer.req_send(v) then
        mixer.answer(false, "Invalid argument")
      end
    elseif r == 'stop' then -- stop generator
      mixer.answer(mixer.req_stop(v))
    end
    mixer.reqs()
    mixer.fill() -- fill buffer/send and rcv
    mixer.write_audio() -- write to audio!
  end
  print "mixer finish"
end

----------------------------- Client side -------------------------------

function mixer.audio(t)
  local idx = 1
  local rc
  while true do
    rc = sys.audio(t, idx)
    if #t == rc + idx - 1 then
      return
    end
    idx = idx + rc
    coroutine.yield()
  end
end

function mixer.coroutine()
  if not mixer.thr then
    mixer.thread()
  else
    while true do
      if mixer.running then
        local e = mixer.thr:err() -- force show peer end error msg
        if e then
          mixer.running = false
          error(e)
        end
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
    local r = {}
    for k, v in ipairs({...}) do
      if type(v) == 'function' then
        local c, e = dump.new(v)
        if not c then
          error(e, 2)
        end
        v = c
      end
      table.insert(r, v)
    end
    mixer.thr:write(table.unpack(r))
    return mixer.thr:read()
  end
end

local sound = {
}
sound.__index = sound

function sound:send(...)
  return mixer.clireq("send",
    { channel = self.channel, id = self.id, ...})
end

function sound:stop(...)
  return mixer.clireq("stop",
    { channel = self.channel, id = self.id })
end

function mixer.new(fn, ...)
  if type(fn) ~= 'function' then
    error("Wrong argument to mixer.add()", 2)
  end
  local ch, id = mixer.clireq('new', fn, {...})
  local snd = {
    channel = ch;
    id = id;
  }
  setmetatable(snd, sound)
  return snd
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
