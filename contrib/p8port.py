#!/usr/bin/env python3
"""p8port.py -- convert a PICO-8 cartridge (.p8) into a rein program (.lua).

Usage:
    python3 contrib/p8port.py cart.p8 [-o cart.lua] [--title TITLE]

Example:
    python3 contrib/p8port.py cart.p8 -o demo/cart.lua
    ./rein demo/cart.lua

The converter:
  * parses the .p8 sections (__lua__, __gfx__, __gff__, __map__, __sfx__, __music__);
  * translates PICO-8 Lua syntax to LuaJIT (compound assignments, \\, !=, ^^,
    &, |, <<, >>, 0b... literals, one-line `if (cond) stmt`, `//` comments);
  * embeds the sprite sheet, map and sprite flags as rein text data;
  * converts all sfx and music patterns into rein tracker text
    (__voices__ / __songs__);
  * prepends a PICO-8 compatibility layer and appends a main loop.

Author: opencode

The compatibility layer covers the API subset used by "reverse raid"
(spr/map/sget/fget, palette remaps via pal(), fillp patterns, print,
btn/btnp, camera, cartdata, sfx/music).  Carts using other calls
(sspr, tline, custom instruments, ...) need those added by hand.
"""

import argparse
import os
import re

NOTE_NAMES = ['c-', 'c#', 'd-', 'd#', 'e-', 'f-', 'f#', 'g-', 'g#', 'a-', 'a#', 'b-']


def note_name(p):
    return NOTE_NAMES[p % 12] + str(p // 12)


def vol_amp(v):
    return int(255 * v / 7 + 0.5)


def hex2(v):
    return '%02x' % v


def note_amp(a):
    amp = vol_amp(a['v'])
    if a['wf'] % 8 == 6 and a['p'] < 12:
        # low-pitch noise is a rumble; keep the engine quieter
        amp = amp // 2
    return amp


# ---------------------------------------------------------------- p8 parsing

def section(lines, name):
    try:
        i = lines.index(name)
    except ValueError:
        return []
    for k in range(i + 1, len(lines)):
        if lines[k].startswith('__') and lines[k].endswith('__'):
            return lines[i + 1:k]
    return lines[i + 1:]


def parse_sfx(text):
    sfx = []
    for line in text:
        line = line.strip()
        if not line:
            continue
        speed = int(line[2:4], 16)
        notes = []
        for i in range(32):
            s = line[8 + i * 5:13 + i * 5]
            notes.append({
                'p': int(s[0:2], 16),
                'wf': int(s[2], 16),
                'v': int(s[3], 16),
                'e': int(s[4], 16),
            })
        sfx.append({'speed': speed, 'notes': notes})
    return sfx


def parse_music(text):
    pats = []
    for line in text:
        line = line.strip()
        if not line:
            continue
        pats.append({
            'flags': int(line[0:2], 16),
            'ch': [int(line[3 + 2 * c:5 + 2 * c], 16) for c in range(4)],
        })
    return pats


# --------------------------------------------------------- audio conversion

def make_voices():
    base = {
        0: 'type sin\n',
        1: 'type sin\n',
        2: 'type saw\nwidth 0.9\n',
        3: 'type square\nwidth 0.5\n',
        4: 'type square\nwidth 0.9\n',
        5: 'type dsf2\noffset 2\nwidth 0.5\n',
        6: 'type noise\nwidth 0.9\nfmul freq 15\n',
        7: 'type dsf2\noffset 1\nwidth 0.7\n',
    }
    env = 'attack 0\ndecay 0\nsustain 1\nrelease 0.01\nset_sustain 1\namp 1\nvolume 0.5\n'
    fade = 'attack 0\ndecay 0.125\nsustain 0\nrelease 0.01\nset_sustain 1\namp 1\nvolume 0.5\n'
    vib = ('lfo_type 0 sin\nlfo_assign 0 fmul\nlfo_freq 0 8\n'
           'lfo_low 0 -0.025\nlfo_high 0 0.025\nlfo_set_loop 0 1\nlfo_set_reset 0 1\n')
    slide = ('lfo_type 0 saw\nlfo_assign 0 fmul\nlfo_freq 0 8\n'
             'lfo_low 0 0\nlfo_high 0 0.3349\nlfo_set_loop 0 0\nlfo_set_reset 0 1\n')

    def drop(high):
        return ('lfo_type 0 saw\nlfo_assign 0 fmul\nlfo_freq 0 16\n'
                'lfo_low 0 0\nlfo_high 0 %s\nlfo_set_loop 0 0\nlfo_set_reset 0 1\n' % high)

    def voice(name, wf, extra):
        return 'voice %s\nbox synth\n%s%s%s' % (name, base[wf], env, extra)

    out = [voice('p8w%d' % wf, wf, '') for wf in range(8)]
    out.append(voice('p8w0f', 0, fade))
    out.append(voice('p8w0d', 0, drop('-0.5')))
    out.append(voice('p8w3d', 3, drop('-0.75')))
    out.append(voice('p8w5v', 5, vib))
    out.append(voice('p8w5f', 5, fade))
    out.append(voice('p8w5sl', 5, slide))
    out.append(voice('p8w6d', 6, drop('-0.75')))
    return '\n'.join(out).rstrip('\n')


def action_voice(a):
    wf = a['wf'] % 8
    if a['e'] == 2 and wf == 5:
        return 'p8w5v'
    if a['e'] == 5 and wf in (0, 5):
        return 'p8w%df' % wf
    if a['e'] == 3 and wf in (0, 3, 6):
        return 'p8w%dd' % wf
    if a['e'] == 1 and wf == 5 and a['np'] != a['p']:
        return 'p8w5sl'
    return 'p8w%d' % wf


def sfx_actions(s, limit=None):
    # one tracker row is 10ms; a pico-8 tick is scaled to 0.75 rows, so a
    # speed 16 note lasts exactly 12 rows (120ms) and speed 8 -> 6 rows.
    R = max(1, int(s['speed'] * 0.75 + 0.5))
    acts = []
    active = False

    def emit(kind, row, **a):
        nonlocal active
        a['t'] = row
        a['kind'] = kind
        acts.append(a)
        active = kind == 'on'

    for i in range(32):
        row = i * R
        if limit is not None and row >= limit:
            break
        d = R
        if limit is not None and row + d > limit:
            d = limit - row
        if d > 0:
            n = s['notes'][i]
            if n['v'] > 0:
                if n['e'] in (6, 7):
                    if s['speed'] <= 8:
                        astep = 2 if n['e'] == 6 else 4
                    else:
                        astep = 4 if n['e'] == 6 else 8
                    ar = max(1, int(astep * R / s['speed'] + 0.5))
                    g = (i // 4) * 4
                    tt = 0
                    while tt < d:
                        step = min(ar, d - tt)
                        gn = s['notes'][g + (tt // ar) % 4]
                        if gn['v'] > 0:
                            emit('on', row + tt, p=gn['p'], wf=n['wf'], v=n['v'],
                                 e=0, d=step, np=gn['p'])
                        elif active:
                            emit('off', row + tt)
                        tt += step
                else:
                    nx = s['notes'][i + 1] if i + 1 < 32 else n
                    emit('on', row, p=n['p'], wf=n['wf'], v=n['v'], e=n['e'],
                         d=d, np=nx['p'])
            elif active:
                emit('off', row)
    if active:
        emit('off', min(32 * R, limit if limit is not None else 32 * R))
    return acts, R


def build_sfx(n, s):
    acts, R = sfx_actions(s)
    byrow = {}
    for a in acts:
        byrow[a['t']] = a
    rs = sorted(byrow)
    out = ['song sfx%d' % n]
    voice = ''
    tempo = -1
    for k, r in enumerate(rs):
        nxt = rs[k + 1] if k + 1 < len(rs) else r + (tempo if tempo > 0 else R)
        gap = nxt - r
        if gap != tempo:
            out.append('@tempo %d' % gap)
            tempo = gap
        a = byrow[r]
        if a['kind'] == 'on':
            v = action_voice(a)
            if voice != v:
                out.append('@voice 1 %s' % v)
                voice = v
            out.append('| %s %s' % (note_name(a['p']), hex2(note_amp(a))))
        else:
            out.append('| === ..')
    return '\n'.join(out)


def pattern_len(pat, sfx):
    for c in range(4):
        sid = pat['ch'][c]
        if sid < 64 and sid < len(sfx):
            return 32 * sfx[sid]['speed']
    return 0


def music_sequence(pats, start=0):
    seq = []
    i = start
    guard = 0
    loop = False
    while i < len(pats) and guard < 256:
        guard += 1
        p = pats[i]
        seq.append(p)
        if p['flags'] & 4:
            break
        if p['flags'] & 2:
            loop = True
            break
        i += 1
    return seq, loop


def build_music(sfx, pats):
    seq, loop = music_sequence(pats)
    tracks = [{} for _ in range(4)]
    allrows = set()
    off = 0
    for pat in seq:
        plen = pattern_len(pat, sfx)
        plenr = int(plen * 0.75 + 0.5)
        if plenr > 0:
            for c in range(4):
                sid = pat['ch'][c]
                if sid < 64 and sid < len(sfx):
                    for a in sfx_actions(sfx[sid], plenr)[0]:
                        r = a['t'] + off
                        tracks[c][r] = a
                        allrows.add(r)
        off += plenr
    out = ['song music']
    if loop:
        out.append('@push -1')
    voices = ['' for _ in range(4)]
    tempo = -1
    rs = sorted(allrows)
    for k, r in enumerate(rs):
        nxt = rs[k + 1] if k + 1 < len(rs) else r + 1
        gap = nxt - r
        if gap != tempo:
            out.append('@tempo %d' % gap)
            tempo = gap
        fields = []
        for c in range(4):
            a = tracks[c].get(r)
            if a and a['kind'] == 'on':
                v = action_voice(a)
                if voices[c] != v:
                    out.append('@voice %d %s' % (c + 1, v))
                    voices[c] = v
                amp = note_amp(a)
                if r < 200:
                    amp = int(amp * r / 200)
                fields.append('%s %s' % (note_name(a['p']), hex2(amp)))
            elif a and a['kind'] == 'off':
                fields.append('=== ..')
            else:
                fields.append('... ..')
        out.append('| %s | %s | %s | %s' % tuple(fields))
    if loop:
        out.append('@pop')
    return '\n'.join(out)


# ------------------------------------------------------------ lua translation

def split_comment(line):
    i = line.find('--')
    if i == -1:
        return line, ''
    return line[:i], line[i:]


BIT_REPL = [
    ("local t=flr(r16)^^flr(r16>>14)^^flr(r16>>13)^^flr(r16>>11)^^1",
     "local t=bit.bxor(bit.bxor(bit.bxor(bit.bxor(flr(r16),flr(bit.rshift(r16,14))),flr(bit.rshift(r16,13))),flr(bit.rshift(r16,11))),1)"),
    ("r16=(r16>>1)&0x7fff", "r16=bit.band(bit.rshift(r16,1),0x7fff)"),
    ("r16|=(t<<15)", "r16=bit.bor(r16,bit.lshift(t,15))"),
    ("return r16&0xffff", "return bit.band(r16,0xffff)"),
    ("local t=flr(r16>>15)^^flr(r16>>13)^^flr(r16>>12)^^flr(r16>>10)^^1",
     "local t=bit.bxor(bit.bxor(bit.bxor(bit.bxor(flr(bit.rshift(r16,15)),flr(bit.rshift(r16,13))),flr(bit.rshift(r16,12))),flr(bit.rshift(r16,10))),1)"),
    ("r16=(r16<<1)&0xffff", "r16=bit.band(bit.lshift(r16,1),0xffff)"),
    ("r16|=(t&1)", "r16=bit.bor(r16,bit.band(t,1))"),
    ("local t=flr(r8>>6)^^flr(r8>>5)^^flr(r8>>4)^^r8",
     "local t=bit.bxor(bit.bxor(bit.bxor(flr(bit.rshift(r8,6)),flr(bit.rshift(r8,5))),flr(bit.rshift(r8,4))),r8)"),
    ("r8=(r8>>1)&0xff", "r8=bit.band(bit.rshift(r8,1),0xff)"),
    ("r8=r8|((t&1)<<7)", "r8=bit.bor(r8,bit.lshift(bit.band(t,1),7))"),
    ("local t=flr(r8>>7)^^flr(r8>>5)^^flr(r8>>4)^^flr(r8>>3)",
     "local t=bit.bxor(bit.bxor(bit.bxor(flr(bit.rshift(r8,7)),flr(bit.rshift(r8,5))),flr(bit.rshift(r8,4))),flr(bit.rshift(r8,3)))"),
    ("r8=(r8<<1)&0xff", "r8=bit.band(bit.lshift(r8,1),0xff)"),
    ("r8|=(t&1)", "r8=bit.bor(r8,bit.band(t,1))"),
    ("local cl=(c>>4)&0xf", "local cl=bit.band(bit.rshift(c,4),0xf)"),
    ("local cr=c&0xf", "local cr=bit.band(c,0xf)"),
    ("local r=(v.c>>7)&0xff", "local r=bit.band(bit.rshift(v.c,7),0xff)"),
]


def convert_div(s):
    # replace atom\atom with flr(atom/atom)
    while True:
        idx = s.find('\\')
        if idx == -1:
            break
        j = idx - 1
        while j >= 0 and s[j] in ' \t':
            j -= 1
        le = j + 1
        while j >= 0 and (s[j].isalnum() or s[j] in '_.]#'):
            j -= 1
        ls = j + 1
        k = idx + 1
        while k < len(s) and s[k] in ' \t':
            k += 1
        rs = k
        while k < len(s) and (s[k].isalnum() or s[k] in '_.'):
            k += 1
        if ls >= le or rs >= k:
            s = s[:idx] + s[idx + 1:]
            continue
        left, right = s[ls:le], s[rs:k]
        s = s[:ls] + 'flr(' + left + '/' + right + ')' + s[k:]
    return s


def convert_bin(m):
    v = float(int(m.group(1), 2))
    if m.group(2):
        v += int(m.group(2), 2) / (2 ** len(m.group(2)))
    return str(int(v)) if v == int(v) else repr(v)


def fix_shorthand(code):
    # pico-8 allows: if (cond) stmt    (no then/end)
    res = code
    while True:
        m = re.search(r'(?<![\w])if\s*\(', res)
        if not m:
            break
        i = m.end() - 1
        depth = 0
        j = i
        while j < len(res):
            if res[j] == '(':
                depth += 1
            elif res[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if j >= len(res):
            break
        cond = res[i + 1:j]
        rest = res[j + 1:]
        st = rest.lstrip()
        cont = ('and', 'or', ',', ']', ')', '==', '~=', '<=', '>=', '<', '>',
                '+', '-', '*', '/', '%', '^', '.', ':')
        if st.startswith('then') or st.startswith(cont) or not st:
            res = res[:m.start()] + 'i\x00f' + res[m.start() + 2:]
            continue
        res = res[:m.start()] + 'if ' + cond + ' then ' + st + ' end'
    return res.replace('\x00', '')


compound = re.compile(r'([A-Za-z_][\w\.\[\]]*)\s*([+\-*/%])=(?!=)')


def translate(lua_lines):
    out = []
    for line in lua_lines:
        line = line.replace('//', '--')
        code, comment = split_comment(line)
        code = code.replace('!=', '~=')
        for a, b in BIT_REPL:
            code = code.replace(a, b)
        code = convert_div(code)
        code = re.sub(r'0b([01]+)(?:\.([01]+))?', convert_bin, code)
        code = compound.sub(lambda m: '%s=%s%s' % (m.group(1), m.group(1), m.group(2)), code)
        code = fix_shorthand(code)
        out.append(code + comment)
    return '\n'.join(out)


# ------------------------------------------------------------------- output

HEAD = r'''-- @@TITLE@@ -- port of @@SRC@@ (pico-8) to the rein engine
-- original game by its pico-8 author
-- converted with contrib/p8port.py (opencode)
-- graphics, level logic and input are ported. sfx and music are
-- embedded as rein tracker text (__voices__ / __songs__).
--
-- run: rein @@OUT@@

local __spr__ = [[
@@ATLAS@@
]]

local __map__ = [[
@@MAP@@
]]

local __gff__ = [[
@@GFF@@
]]

local __voices__ = [[
@@VOICES@@
]]

local __songs__ = [[
@@SONGS@@
]]

-- ===== pico-8 compatibility layer =====

gfx.win(128, 128)
gfx.border(0)
gfx.fg(6)
gfx.bg(0)
sys.title("@@TITLE@@")

local bit = bit
local SPRH = @@SPRH@@

local TAU = math.pi * 2
function flr(x) return math.floor(x) end
function ceil(x) return math.ceil(x) end
function abs(x) return math.abs(x) end
function sgn(x)
  if x > 0 then return 1 elseif x < 0 then return -1 end
  return 0
end
function sin(x) return math.sin(x * TAU) end
function cos(x) return math.cos(x * TAU) end
function atan2(dx, dy) return (math.atan2(dy, dx) / TAU) % 1 end
function min(a, b) if a < b then return a end return b end
function max(a, b) if a > b then return a end return b end
function rnd(a)
  if type(a) == 'table' then return a[math.random(#a)] end
  if a == nil then return math.random() end
  return math.random() * a
end
function tostr(v) return tostring(v) end
function add(t, v) table.insert(t, v) return v end
function del(t, v)
  for i = 1, #t do
    if t[i] == v then return table.remove(t, i) end
  end
end
function all(t)
  local i = 0
  t = t or {}
  return function() i = i + 1 return t[i] end
end
function printh(...) end

local BTN = {
  [0] = { 'left' }, [1] = { 'right' },
  [2] = { 'up' }, [3] = { 'down' },
  [4] = { 'z', 'space' }, [5] = { 'x', 'c' },
}
local bstate, bprev = {}, {}
local P8BTN
function btn(i) return bstate[i] or false end
function btnp(i) return (bstate[i] and not bprev[i]) or false end
function input_frame()
  for i = 0, 5 do
    bprev[i] = bstate[i]
    local v = false
    if P8BTN and P8BTN[i] ~= nil then
      v = P8BTN[i]
    else
      for _, k in ipairs(BTN[i]) do
        if input.keydown(k) then v = true break end
      end
    end
    bstate[i] = v
  end
end

local sprdata = gfx.new(__spr__)
local c14 = { gfx.pal(14) }
local c15 = { gfx.pal(15) }
local function make_variant(r14, r15)
  if not r14 and not r15 then return sprdata end
  local p = gfx.new(128, SPRH)
  sprdata:copy(p)
  for y = 0, SPRH - 1 do
    for x = 0, 127 do
      local r, g, b, a = p:val(x, y)
      if a ~= 0 then
        if (r14 and r == c14[1] and g == c14[2] and b == c14[3]) or
          (r15 and r == c15[1] and g == c15[2] and b == c15[3]) then
          p:val(x, y, 0)
        end
      end
    end
  end
  return p
end
local a14 = make_variant(true, false)
local a15 = make_variant(false, true)
local a1415 = make_variant(true, true)
local pr14, pr15 = false, false
function pal(c, t)
  if c == nil then
    pr14, pr15 = false, false
    return
  end
  if t == 0 then
    if c == 14 then pr14 = true end
    if c == 15 then pr15 = true end
  end
end
local function cur_sprdata()
  if pr14 and pr15 then return a1415 end
  if pr14 then return a14 end
  if pr15 then return a15 end
  return sprdata
end

local atlas_key = {}
atlas_key[sprdata] = 's'
atlas_key[a14] = '14'
atlas_key[a15] = '15'
atlas_key[a1415] = '1415'
function spr(n, x, y, w, h, fx, fy)
  gfx.spr(cur_sprdata(), n, x, y, w or 1, h or 1, fx, fy)
end

local maplines = {}
for l in __map__:gmatch('[^\n]+') do
  maplines[#maplines + 1] = l
end
function map(mx, my, sx, sy, w, h)
  for y = 0, h - 1 do
    local line = maplines[my + y + 1]
    if line then
      for x = 0, w - 1 do
        local t = tonumber(line:sub((mx + x) * 2 + 1, (mx + x) * 2 + 2), 16)
        if t and t ~= 0 then
          spr(t, sx + x * 8, sy + y * 8)
        end
      end
    end
  end
end

local gffdata = (__gff__:gsub('%s', ''))
function fget(n, f)
  local b = tonumber(gffdata:sub(n * 2 + 1, n * 2 + 2), 16) or 0
  return bit.band(b, bit.lshift(1, f)) ~= 0
end

local revpal = {}
for i = 1, 15 do
  local r, g, b = gfx.pal(i)
  revpal[r * 65536 + g * 256 + b] = i
end
function sget(x, y)
  if x < 0 or y < 0 or x > 127 or y > SPRH - 1 then return 0 end
  local r, g, b, a = sprdata:val(x, y)
  if a == 0 then return 0 end
  return revpal[r * 65536 + g * 256 + b] or 0
end

function cls(c) screen:clear(c or 0) end
function pset(x, y, c) screen:pixel(x, y, c) end
function line(x1, y1, x2, y2, c) screen:line(x1, y1, x2, y2, c) end
function camera(x, y)
  if x then screen:offset(x, y) else screen:nooffset() end
end

local fillbits = false
local patcache = {}
local function getpat(bits, col)
  local ib = flr(bits)
  local k = ib * 16 + col
  local p = patcache[k]
  if not p then
    p = gfx.new(4, 4)
    for y = 0, 3 do
      for x = 0, 3 do
        local v = bit.rshift(0x8000, y * 4 + x)
        if bit.band(ib, v) == 0 then
          p:pixel(x, y, col)
        else
          p:val(x, y, -1)
        end
      end
    end
    patcache[k] = p
  end
  return p
end
function fillp(p) fillbits = p end
function circfill(x, y, r, c)
  if fillbits then
    screen:fill_circle(x, y, r, getpat(fillbits, c))
  else
    screen:fill_circle(x, y, r, c)
  end
end
function rectfill(x1, y1, x2, y2, c)
  if fillbits then
    screen:fill_rect(x1, y1, x2, y2, getpat(fillbits, c))
  else
    screen:fill_rect(x1, y1, x2, y2, c)
  end
end

local function p8str(t)
  t = tostring(t)
  t = t:gsub('\240\159\133\190', '\194\142') -- O key
  t = t:gsub('\226\153\165', '\194\135') -- heart
  t = t:gsub('%a', string.upper)
  return t
end
function print(t, x, y, c)
  return gfx.print(p8str(t), x or 0, y or 0, c, false)
end

-- ===== pico-8 sfx/music playback =====

local audio = {}
local audio_ok = mixer.voices(__voices__)
audio_ok = audio_ok and mixer.songs(__songs__)

local chans = {}
local music_id

function audio.sfx(n)
  if not n or n < 0 then return end
  for c = 1, 4 do
    local ch = chans[c]
    if ch and ch.n == n and ch.id and mixer.status(ch.id) then
      mixer.stop(ch.id)
      ch.id = mixer.play('sfx' .. n)
      return
    end
  end
  for c = 1, 4 do
    local ch = chans[c]
    if not ch or not ch.id or not mixer.status(ch.id) then
      chans[c] = { n = n, id = mixer.play('sfx' .. n) }
      return
    end
  end
  local ch = chans[1]
  if ch and ch.id then mixer.stop(ch.id) end
  chans[1] = { n = n, id = mixer.play('sfx' .. n) }
end

function audio.music(n, fade)
  if n == nil then return end
  if n < 0 then
    if music_id then
      mixer.stop(music_id, fade and fade / 1000 or 0)
      music_id = nil
    end
    return
  end
  if music_id then
    mixer.stop(music_id)
    music_id = nil
  end
  if n == 0 then
    music_id = mixer.play('music')
  end
end

function music(n, fade) return audio.music(n, fade) end
function sfx(n) return audio.sfx(n) end

local cart = {}
local cartpath
local dumper
local lastsave = 0
function cartdata(name)
  local dir = sys.appdir(name)
  if not dir then return false end
  cartpath = dir .. '/cart.dat'
  dumper = require 'dump'
  local t = dumper.load(cartpath)
  if type(t) == 'table' then cart = t end
  return true
end
function dget(i) return cart[i] end
function dset(i, v)
  cart[i] = v
  local now = sys.time()
  if dumper and cartpath and now - lastsave > 2 then
    lastsave = now
    dumper.save(cartpath, cart)
  end
end

-- ===== game =====
'''

TAIL = r'''
-- ===== main loop =====

_init()
local update = _update60 or _update or function() end
local fps = _update60 and 1 / 60 or 1 / 30
while sys.running() do
  input_frame()
  update()
  _draw()
  gfx.flip(fps)
end
'''


def credits_of(lua_lines, outname):
    title = None
    author = None
    for line in lua_lines:
        s = line.strip()
        if not s:
            continue
        if s.startswith('--') and not s.startswith('--[['):
            t = s.lstrip('-').strip()
            if t and title is None:
                title = t
            elif t and author is None:
                author = re.sub(r'^(by|ny)\s+', 'by ', t, flags=re.I)
                break
        else:
            break
    if title is None:
        title = os.path.splitext(os.path.basename(outname))[0]
    return title, author


def main():
    ap = argparse.ArgumentParser(description='pico-8 .p8 -> rein .lua converter')
    ap.add_argument('input', help='input .p8 cartridge')
    ap.add_argument('-o', '--output', help='output .lua file')
    ap.add_argument('--title', help='window title (default: first comment of the cart)')
    args = ap.parse_args()

    src = args.input
    out = args.output or os.path.splitext(src)[0] + '.lua'

    lines = open(src, 'r', encoding='utf-8').read().split('\n')
    lua = section(lines, '__lua__')
    gfx = [l for l in section(lines, '__gfx__') if l.strip()]
    mapsec = [l for l in section(lines, '__map__') if l.strip()]
    gffsec = [l for l in section(lines, '__gff__') if l.strip()]
    sfx = parse_sfx(section(lines, '__sfx__'))
    pats = parse_music(section(lines, '__music__'))

    atlas = ['0123456789abcdef']
    for l in gfx:
        atlas.append(''.join('-' if c == '0' else c for c in l))
    if len(atlas) == 1:
        atlas += ['-' * 128] * 64
    atlas_text = '\n'.join(atlas)
    spr_h = len(atlas) - 1

    voices_text = make_voices()
    songs = [build_sfx(n, s) for n, s in enumerate(sfx)]
    if pats:
        songs.append(build_music(sfx, pats))
    songs_text = '\n\n'.join(songs)

    title, author = credits_of(lua, out)
    title = args.title or title
    game_code = translate(lua)

    head = HEAD.replace('@@TITLE@@', title)
    if author:
        head = head.replace('-- original game by its pico-8 author',
                            '-- original: %s' % author)
    head = head.replace('@@SRC@@', os.path.basename(src))
    head = head.replace('@@OUT@@', out)
    head = head.replace('@@SPRH@@', str(spr_h))
    head = head.replace('@@ATLAS@@', atlas_text)
    head = head.replace('@@MAP@@', '\n'.join(mapsec))
    head = head.replace('@@GFF@@', '\n'.join(gffsec))
    head = head.replace('@@VOICES@@', voices_text)
    head = head.replace('@@SONGS@@', songs_text)

    open(out, 'w', encoding='utf-8').write(head + game_code + '\n' + TAIL)

    bad = []
    for n, line in enumerate(game_code.split('\n'), 1):
        code, _ = split_comment(line)
        if re.search(r'(?<![<>=~])[|&]|<<|>>|\^\^|\\', code):
            bad.append((n, line))
    if bad:
        print('warning: pico-8 operators left in the code:')
        for n, line in bad[:40]:
            print('  %d: %s' % (n, line))
    print('written %s' % out)


if __name__ == '__main__':
    main()
