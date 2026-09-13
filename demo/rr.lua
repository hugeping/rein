-- reverse raid -- port of rr.p8 (pico-8) to the rein engine
-- original: by hugeping
-- converted with contrib/p8port.py (opencode)
-- graphics, level logic and input are ported. sfx and music are
-- embedded as rein tracker text (__voices__ / __songs__).
--
-- run: rein demo/rr.lua
local snd = require "sfx"

local dprint = print
local __spr__ = [[
0123456789abcdef
--------1111111dd-------d-------1111111d1111111d--------111111111111111d--------d---------------d---------1---------------------
--------111f11111d------1d------1f1111d-1111f1d---------111111f1d1f11111--------d---------------d--------1dd--------ffd----7d---
--7--7--1111111d111-----11d-----11111d--111111d---------11f111111111111d------d666d-----------d666ddd-----dd1------61c6----fd---
---77---1f11111111d-----f11d----1111d---11111d----------1f111111d111f111---dddfcccfddd------ddfcccf11ddd---d1-----61cc6----11---
---77---1111111d11d-----1111d---111d----11111d-----dd---111111111111111d-ddd11f111f11ddd-ddd11f111f--11----dd1----66cc----ddd1--
--7--7--1111f111111-----11111d--11d-----1f1111d---d11d--11f11111d1111111--11--f676f--11---11--f676f--df-----d1-----fd--------d--
--------1111111d1d------111f11d-1d------111111d--d1111d-11111f11111f111d--fd---6-6---df---fd---6-6---d7-----d-------------------
--------11111111d-------1111111dd-------1111f11dd111f11d11111111d1111111--7d---------d7---7d------------------------------------
ffffffffd1111111-------d-------dd1111111d1111111d111111d--dd11---dddddd----aa------aa------aa------aa---------------------------
ffffffff11111111------d1------d1-d111f11-d1f1111-d1f11d--d1111d-d111111d----8-------9-------9-------8---------------------------
ffffffffd11f1111-----111-----d11--d11111-d111111--d11d--11111f1-11111111------------8--------------e-----------------------11---
fffff1ff11111111-----d11----d111---d1111--d11111---dd---d111111d1f11111f----8------8-------8-------8----a-8-----98---------f61--
ffffffffd1111111-----d11---d1111----d111--d111f1--------11f1111111111111--------------------8-----------98------a--8-------ff1--
fff1ffff11111f11-----111--d111f1-----d11-d111111--------11111f1111111111----------------------------------------------------f1--
ffffffffd1111111------d1-d11f111------d1-d11f111---------11111d-11111f11--------------------------------------------------------
ffffffff11f11111-------dd1111111-------dd1111111----------11dd--11111111--------------------------------------------------------
-------------------------------------------------cccccc--999999-----------------------------------------------------------------
---555-----555---------------------9-------c----77ffff6677ffff66------------------------18111111111911111111131----555-----11---
--22222---22222--------------------9-------c----77ffff6677ffff66--------------d---d666d-18888889999999993333331---22222---cd1---
--d8555---d9555--999999--777777----9-------c----ee888888ee888888-----------dddf---fcccf-18111111111911111111131---d8555---cdd1--
--33333---3b333--------------------9-------c----ee888888ee888888---------ddd11f---f111f---------------------------33333----dd1--
---555-----555---------------------9-------c----ee888888ee888888----------11--f---f676f----------------------------555-----dd1--
-----------------------------------9-------c----77ffff6677ffff66-------------------6-6--------------------------------------d---
------------------------------------------------77ffff6677ffff66----------------------------------------------------------------
------------------------------------------------77ffff6677ffff66---e8------e8---7575757-57575757--------------------------------
1d------1d--------------------------------------77ffff6677ffff66---76------76---7575757-57575757-d-------d----------------------
1d------1d------ccccccccccccccccccccccccccccccccee888888ee888888---76------76----23322---23322---dd------dd--------88------99---
1d1ff88-1d1ffee-d8d1d1d1d1d9d1d1d1d1dad1d1d1d1dbee888888ee888888-333333--333333-43b7fff-43b7fff-7a6666e8766666e8---88------99---
1d1ff88-1d1ffee-ccccccccccccccccccccccccccccccccee888888ee888888-575757--757575-43bb34--43bb34--addddde87adddde8---dd------dd---
1d------1d------1111111111111111111111111111111177ffff6677ffff667499499559949947-23322---23322---55------55--------dd------dd---
1d------1d--------------------------------------77ffff6677ffff6659949947749949957575757-57575757-5-------5---------dd------dd---
-------------------------------------------------cccccc--999999--757575--575757-7575757-57575757------------------cccc----cccc--
------------------------11111111----------------eeeeeeeeeeeeeee-eeeeeeeeeeeeeeeeeeeeeeeeeee-------------------------------------
--1--------11-----------11111111----------------eddddeedddddede-ededddddeddddeeedddeeddddde-------------------------------------
-111------111-----------11111111-----11111------edeeededeeeeede-ededeeeeedeeededeeededeeeee-------------------------------------
11111-----1111------1---f1f1f1f1----16d1d11-----edeeededeeeeedeeededeeeeedeeededeeeeedeeee--------------------------------------
111111---11111-----111--1f1f1f1f---16df61de1----eddddeeddddeeededeeddddeeddddeeedddeedddde--------------------------------------
1111111--111111---11111-ffffffff--16dff6d1de1---edeeededeeeeeededeedeeeeedeeedeeeeededeeee--------------------------------------
111111111111111--1111111f1f1f1f1--1d6f66dd11e---ede-ededeeeeeededeedeeeeede-ededeeededeeeee-------------------------------------
111111111111111111111111ffffffff--16df6dd1de1---ede-ededddddeeedeeedddddede-edeedddeeddddde-------------------------------------
----------------------------------1d66dddd11e---eee-eeeeeeeee-eee-eeeeeeeee-eee-eeeeeeeeeee-------------------------------------
-------------1----1-------1-------11ddddd11e1--------------eeeee---eeee---ee--eeee----------------------------------------------
------------111--111-1---111-------11d1d11e1--------------e8888e--e8888e-e88ee8888e---------------------------------------------
---1-------111111111111-11111-------1e1e1e1--------------e88ee88-e88ee88ee88ee88e88e--------------------------------------------
--111-----11111111111111111111-------1e1e1---------------e88ee88-e88ee88ee88ee88e88e--------------------------------------------
-11111---1111111111111111111111-------------------------e888888ee8888888e88ee88ee88e--------------------------------------------
1111111-111111111111111111111111------------------------e88ee888e88eee88e88ee88ee88e--------------------------------------------
11111111111111111111111111111111-----------------------e888eee88e88e-e88e88ee88888e---------------------------------------------
11111111-daaaad-11111111--------------------------------------------------------------------------------------------------------
11111111d116d11d111111f1--------------------------------------------------------------------------------------------------------
111111111116d11111f11111--------------------------------------------------------------------------------------------------------
f1f1f1f11f16d11f1f111111--------------------------------------------------------------------------------------------------------
1f1f1f1f1116d11111111111--------------------------------------------------------------------------------------------------------
ffffffff1116dddddddddddd--------------------------------------------------------------------------------------------------------
f1f1f1f11116666666666666--------------------------------------------------------------------------------------------------------
fddddddf1111111111111111--------------------------------------------------------------------------------------------------------
6d6d6d6d6d6d6d6d--dd-d---1-1-1-1------------------------------------------------------------------------------------------------
d1111111d1111111--d-dd--1c1c1c1c------------------------------------------------------------------------------------------------
618dbdc161ed3d21--dd-d--dddddddd------------------------------------------------------------------------------------------------
d1111111d1111111--d-dd--1d1d1d1d------------------------------------------------------------------------------------------------
61dedcd161d8d5d1--dd-d--d1d1d1d1------------------------------------------------------------------------------------------------
d1111111d1111111--d-dd--dddddddd------------------------------------------------------------------------------------------------
615d5de1618dbda1--dd-d--1c1c1c1c------------------------------------------------------------------------------------------------
d1111111d1111111--d-dd---1-1-1-1------------------------------------------------------------------------------------------------
]]

local __map__ = [[
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5050514041424142515253415042415152405050410000000000004250515253000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4343434343434343434343434343434343434343434343434343434343434343000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
]]

local __gff__ = [[
0000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000010101010000000000000000010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010101000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
]]

local __voices__ = [[
voice p8w0
box synth
type sin
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w1
box synth
type sin
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w2
box synth
type pwm
width 0.6
attack 0.01
decay 0
sustain 1
release 0.01
set_sustain 1
amp 0.2
volume 0.5

box filter
# filter
volume 0.5
mode highpass
width 0.9

voice p8w3
box synth
type square
width 0.5
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w4
box synth
type square
width 0.9
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w5
box synth
type dsf2
offset 2
width 0.5
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w6
box synth
type noise
width 0.9
fmul freq 15
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

box filter
# filter
volume 1
mode lowpass
width 0.3

voice p8w7
box synth
type dsf2
offset 1
width 0.7
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w0f
box synth
type sin
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5
attack 0.002
decay 0.125
sustain 0
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w0d
box synth
fmul freq 0.5
type square
width 0
decay 0.2
sustain 0
release 0.01
volume 1
lfo_assign 0 freq
lfo_type 0 saw
lfo_freq 0 15
lfo_low 0 100
lfo_high 0 -100
lfo_set_loop 0 0
lfo_assign 1 width
lfo_type 1 saw
lfo_freq 1 15
lfo_low 1 0.5
lfo_high 1 -0.5
lfo_set_loop 1 0

voice p8w3d
box synth
type square
width 0.5
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5
lfo_type 0 saw
lfo_assign 0 fmul
lfo_freq 0 16
lfo_low 0 0
lfo_high 0 -0.75
lfo_set_loop 0 0
lfo_set_reset 0 1

voice p8w5v
box synth
type dsf2
offset 2
width 0.5
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5
lfo_type 0 sin
lfo_assign 0 fmul
lfo_freq 0 8
lfo_low 0 -0.025
lfo_high 0 0.025
lfo_set_loop 0 1
lfo_set_reset 0 1

voice p8w5f
box synth
type dsf2
offset 2
width 0.5
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5
attack 0.002
decay 0.125
sustain 0
release 0.01
set_sustain 1
amp 1
volume 0.5

voice p8w5sl
box synth
type dsf2
offset 2
width 0.5
attack 0.002
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.5
lfo_type 0 saw
lfo_assign 0 fmul
lfo_freq 0 8
lfo_low 0 0
lfo_high 0 0.3349
lfo_set_loop 0 0
lfo_set_reset 0 1

voice p8w6d
box synth
type lin_band_noise
volume 0.5
offset 10000
width 10000
fmul freq 0.4
decay 0.15
sustain 0
release 0
lfo_assign 1 freq
lfo_type 1 saw
lfo_freq 1 5
lfo_low 1 9500
lfo_high 1 5000
lfo_set_loop 1 0

voice eng
box synth
type lin_noise
width 0.9
fmul freq 15
attack 0
decay 0
sustain 1
release 0.01
set_sustain 1
amp 1
volume 0.3

box filter
# filter
volume 0.7
mode lowpass
width 0.1
]]

local __songs__ = [[
song sfx0
@tempo 1
@voice 1 p8w5
| b-5 b6
| d#5 b6
| g#4 b6
| f-4 b6
| d-4 b6
| c-4 b6
| a#3 b6
| g-3 b6
| e-3 b6
| c#3 b6
| b-2 b6
| a#2 b6
| g-2 b6
| f-2 b6
| d#2 b6
| c-2 b6
| g#1 b6
| f#1 b6
| g-1 b6
| f-1 b6
| c#1 b6
| c-1 b6
| c-1 b6
| === ..

song sfx1
@tempo 1
@voice 1 eng
| c-1 66

song sfx2
@tempo 2
@voice 1 p8w6
| d#6 ff
| e-5 ff
| a#4 ff
| f-4 ff
| d-4 ff
| c-4 ff
| c#4 ff
| c#4 ff
| c#4 ff
| d#4 ff
| c#4 ff
| a-3 ff
| f#3 ff
| d-3 db
| g#2 b6
| f-2 b6
| c#2 92
| b-1 49
| g-1 49
| f#1 36
| e-1 24
| d#1 12
| d-1 12
| c-1 12
| === ..

song sfx3
@tempo 6
@voice 1 p8w0
| a-4 b6
| g#5 b6
| f-3 b6
| d-3 b6
| a#3 b6
| a-4 b6
| f-5 b6
| d-6 b6
| === ..

song sfx4
@tempo 1
@voice 1 p8w2
| f-4 6d
| d#4 6d
| d-4 6d
| c-4 6d
| b-3 6d
| a-3 6d
| g-3 6d
| f-3 6d
| d#3 6d
| c#3 6d
| a#2 6d
| a-2 6d
| f#2 6d
| d#2 6d
| c-2 6d
| b-1 6d
| a#1 6d
| g-1 92
| e-1 92
| c#1 92
| c-1 92
| c-1 92
| === ..

song sfx5
@tempo 12
@voice 1 p8w0
| d#4 b6
| a#4 b6
| d#5 b6
| f-5 b6
| a#5 b6
| d#6 b6
| d#6 b6
| === ..

song sfx6
@tempo 1
@voice 1 p8w6
| d#6 b6
| f#5 b6
| d-5 b6
| c-5 b6
| a-4 b6
| g-4 b6
| f#4 b6
| e-4 b6
| c#4 b6
| b-3 b6
| f-3 b6
| c#3 b6
| g#2 b6
| d#2 b6
| g#1 5b
| d#1 5b
| c#1 5b
| c-1 5b
| c-1 5b
| === ..

song sfx7
@tempo 1
@voice 1 p8w5
| b-5 b6
| f#5 b6
| c#5 b6
| a-4 b6
| e-4 b6
| b-3 b6
| g#3 b6
| f#3 b6
| c#3 b6
| a#2 b6
| g#2 b6
| f-2 b6
| e-2 b6
| d#2 b6
| c#2 b6
| a#1 b6
| g#1 b6
| g-1 b6
| f-1 b6
| === ..

song sfx8
@tempo 5
@voice 1 p8w7
| f-1 b6
| d#2 b6
| g-2 b6
| d#3 b6
| a#3 b6
| d#4 b6
| a#4 b6
| f-5 b6
| a#5 b6
| d#6 b6
| a#5 b6
| g-5 b6
| c-6 b6
| a#5 b6
| c-6 b6
| a#5 b6
| c-6 b6
| a#5 b6
| c-6 b6
| a#5 b6
| g-5 b6
| a-5 b6
| g-5 b6
| d#5 b6
| g-4 b6
| a#4 b6
| f-4 b6
| c-4 b6
| f-3 b6
| c-3 b6
| g-2 b6
| g-1 b6
| === ..

song sfx9
@tempo 6
@voice 1 p8w0
| a-3 b6
| e-4 b6
| === ..

song sfx10
@tempo 4
@voice 1 p8w5
| c-1 ff
| c-1 ff
| c#1 ff
| c#1 ff
| d-1 db
| d-1 b6
| d#1 b6
| f-1 b6
| f-1 b6
| f#1 b6
| g-1 b6
| a-1 b6
| a#1 b6
| c-2 b6
| c#2 b6
| c#2 b6
| d#2 b6
| f-2 b6
| g-2 b6
| g#2 b6
| b-2 b6
| c-3 b6
| d-3 b6
| e-3 b6
| g-3 b6
| b-3 b6
| c#4 b6
| f#4 b6
| g#4 b6
| c-5 b6
| f-5 b6
| a-5 b6
| === ..

song sfx11
@tempo 4
@voice 1 p8w6
| e-1 5b
| f-1 5b
| f-1 5b
| f#1 5b
| g-1 5b
| g#1 5b
| g#1 5b
| b-1 5b
| b-1 5b
| c-2 b6
| c#2 b6
| c#2 b6
| d-2 b6
| d-2 b6
| d#2 b6
| e-2 b6
| f-2 b6
| g-2 b6
| a-2 b6
| b-2 b6
| d-3 b6
| e-3 b6
| f-3 b6
| g-3 b6
| a#3 b6
| c-4 b6
| e-4 b6
| g-4 b6
| c-5 b6
| f-5 b6
| c-6 b6
| d#6 b6
| === ..

song music
@push -1
@tempo 12
@voice 2 p8w5
| ... .. | d-3 00 | ... .. | ... ..
@voice 2 p8w5v
| ... .. | d-3 0a | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 20 | ... .. | ... ..
@voice 2 p8w5
| ... .. | d-3 2b | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5v
| ... .. | d-3 41 | ... .. | ... ..
| ... .. | d-3 4c | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | f-3 62 | ... .. | ... ..
| ... .. | e-3 6d | ... .. | ... ..
| ... .. | c-3 78 | ... .. | ... ..
| ... .. | d-3 83 | ... .. | ... ..
| ... .. | d-3 8d | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 a3 | ... .. | ... ..
| ... .. | d-3 ae | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
| ... .. | c-3 b6 | ... .. | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
| ... .. | c-3 b6 | ... .. | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | d-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
@voice 2 p8w5
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5v
@voice 3 p8w6d
| ... .. | d-3 b6 | c-3 b6 | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
@voice 3 p8w0d
| ... .. | d-3 b6 | c-2 ff | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w6d
| ... .. | d-3 b6 | c-3 b6 | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | e-3 b6 | === .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | c-3 b6 | c-2 b6 | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w6d
| ... .. | c-3 b6 | c-3 ff | ... ..
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | c-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w6d
| ... .. | e-3 b6 | c-3 b6 | ... ..
| ... .. | e-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | g-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | g-3 b6 | === .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
@voice 3 p8w6d
| ... .. | g-3 b6 | c-3 b6 | ... ..
| ... .. | g-3 b6 | === .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
@voice 3 p8w0d
| ... .. | d-3 b6 | c-2 ff | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
@voice 3 p8w6d
| ... .. | d-3 b6 | c-3 b6 | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | e-3 b6 | === .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | f-3 b6 | c-2 b6 | ... ..
@voice 2 p8w5v
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
@voice 3 p8w6d
| ... .. | f-3 b6 | c-3 ff | ... ..
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | c-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
@voice 2 p8w5sl
| ... .. | c-3 b6 | ... .. | ... ..
@voice 2 p8w5v
@voice 3 p8w6d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w3d
| ... .. | g-3 b6 | c-3 b6 | ... ..
| ... .. | g-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | d-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
@voice 2 p8w5
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5v
@voice 3 p8w6d
| ... .. | d-3 b6 | c-3 b6 | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
@voice 3 p8w0d
| ... .. | d-3 b6 | c-2 ff | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w6d
| ... .. | d-3 b6 | c-3 b6 | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | e-3 b6 | === .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | c-3 b6 | c-2 b6 | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w6d
| ... .. | c-3 b6 | c-3 ff | ... ..
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | c-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w6d
| ... .. | e-3 b6 | c-3 b6 | ... ..
| ... .. | e-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 1 p8w5v
@voice 2 p8w5
@voice 3 p8w0d
@voice 4 p8w0f
| d-2 b6 | d-3 b6 | c-2 ff | f-4 6d
@voice 2 p8w5v
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| f-2 b6 | === .. | ... .. | d-4 6d
| e-2 b6 | d-3 b6 | ... .. | e-4 6d
@voice 2 p8w5
| f-2 b6 | d-3 b6 | ... .. | f-4 6d
| e-2 b6 | === .. | ... .. | e-4 6d
@voice 2 p8w5v
@voice 3 p8w6d
| d-2 b6 | d-3 b6 | c-3 b6 | f-4 6d
| d-2 b6 | d-3 b6 | === .. | e-4 6d
@tempo 3
@voice 1 p8w5
| d-2 b6 | === .. | ... .. | d-4 6d
| d-2 b6 | ... .. | ... .. | ... ..
| d-2 b6 | ... .. | ... .. | ... ..
| d-2 b6 | ... .. | ... .. | ... ..
@tempo 12
@voice 1 p8w5v
| d-2 b6 | f-3 b6 | ... .. | e-4 6d
| d-2 b6 | e-3 b6 | ... .. | f-4 6d
@voice 1 p8w5f
| d-2 b6 | c-3 b6 | ... .. | e-4 6d
@voice 3 p8w0d
| === .. | d-3 b6 | c-2 ff | f-4 6d
@voice 1 p8w5v
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| d-2 b6 | === .. | ... .. | d-4 6d
| f-2 b6 | d-3 b6 | ... .. | e-4 6d
| e-2 b6 | d-3 b6 | ... .. | f-4 6d
| f-2 b6 | === .. | ... .. | e-4 6d
@voice 3 p8w6d
| e-2 b6 | d-3 b6 | c-3 b6 | f-4 6d
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| d-2 b6 | === .. | ... .. | d-4 6d
@voice 3 p8w3d
| d-2 b6 | f-3 b6 | c-3 b6 | e-4 6d
| d-2 b6 | e-3 b6 | === .. | f-4 6d
| d-2 b6 | a-2 b6 | ... .. | e-4 6d
@voice 1 p8w5
@voice 2 p8w5
@voice 3 p8w0d
| c-2 b6 | c-3 b6 | c-2 b6 | e-4 6d
@voice 1 p8w5v
@voice 2 p8w5v
| c-2 b6 | c-3 b6 | === .. | d-4 6d
| c-2 b6 | === .. | ... .. | c-4 6d
| c-2 b6 | c-3 b6 | ... .. | d-4 6d
| c-2 b6 | c-3 b6 | ... .. | e-4 6d
| c-2 b6 | === .. | ... .. | d-4 6d
@voice 3 p8w6d
| c-2 b6 | c-3 b6 | c-3 ff | e-4 6d
| c-2 b6 | c-3 b6 | === .. | d-4 6d
@tempo 6
| c-2 b6 | c-3 b6 | ... .. | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | f-3 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | e-3 b6 | ... .. | c-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | a-2 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| c-2 b6 | c-3 b6 | c-2 ff | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@voice 2 p8w5v
| c-2 b6 | c-3 b6 | === .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | === .. | ... .. | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | c-3 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@tempo 12
| === .. | c-3 b6 | ... .. | c-4 6d
| ... .. | === .. | ... .. | d-4 6d
@voice 3 p8w6d
| ... .. | e-3 b6 | c-3 b6 | e-4 6d
| ... .. | e-3 b6 | === .. | d-4 6d
| ... .. | === .. | ... .. | e-4 6d
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | d-4 6d
| ... .. | f-3 b6 | === .. | c-4 6d
| ... .. | === .. | ... .. | d-4 6d
@voice 2 p8w5
@voice 3 p8w0d
| d-2 b6 | d-3 b6 | c-2 ff | f-4 6d
@voice 2 p8w5v
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| f-2 b6 | === .. | ... .. | d-4 6d
| e-2 b6 | d-3 b6 | ... .. | e-4 6d
@voice 2 p8w5
| f-2 b6 | d-3 b6 | ... .. | f-4 6d
| e-2 b6 | === .. | ... .. | e-4 6d
@voice 2 p8w5v
@voice 3 p8w6d
| d-2 b6 | d-3 b6 | c-3 b6 | f-4 6d
| d-2 b6 | d-3 b6 | === .. | e-4 6d
@tempo 3
@voice 1 p8w5
| d-2 b6 | === .. | ... .. | d-4 6d
| d-2 b6 | ... .. | ... .. | ... ..
| d-2 b6 | ... .. | ... .. | ... ..
| d-2 b6 | ... .. | ... .. | ... ..
@tempo 12
@voice 1 p8w5v
| d-2 b6 | f-3 b6 | ... .. | e-4 6d
| d-2 b6 | e-3 b6 | ... .. | f-4 6d
@voice 1 p8w5f
| d-2 b6 | c-3 b6 | ... .. | e-4 6d
@voice 3 p8w0d
| === .. | d-3 b6 | c-2 ff | f-4 6d
@voice 1 p8w5v
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| d-2 b6 | === .. | ... .. | d-4 6d
| f-2 b6 | d-3 b6 | ... .. | e-4 6d
| e-2 b6 | d-3 b6 | ... .. | f-4 6d
| f-2 b6 | === .. | ... .. | e-4 6d
@voice 3 p8w6d
| e-2 b6 | d-3 b6 | c-3 b6 | f-4 6d
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| d-2 b6 | === .. | ... .. | d-4 6d
@voice 3 p8w3d
| d-2 b6 | f-3 b6 | c-3 b6 | e-4 6d
| d-2 b6 | e-3 b6 | === .. | f-4 6d
| d-2 b6 | a-2 b6 | ... .. | e-4 6d
@voice 1 p8w5
@voice 2 p8w5
@voice 3 p8w0d
| c-2 b6 | c-3 b6 | c-2 b6 | e-4 6d
@voice 1 p8w5v
@voice 2 p8w5v
| c-2 b6 | c-3 b6 | === .. | d-4 6d
| c-2 b6 | === .. | ... .. | c-4 6d
| c-2 b6 | c-3 b6 | ... .. | d-4 6d
| c-2 b6 | c-3 b6 | ... .. | e-4 6d
| c-2 b6 | === .. | ... .. | d-4 6d
@voice 3 p8w6d
| c-2 b6 | c-3 b6 | c-3 ff | e-4 6d
| c-2 b6 | c-3 b6 | === .. | d-4 6d
@tempo 6
| c-2 b6 | c-3 b6 | ... .. | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | f-3 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | e-3 b6 | ... .. | c-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | a-2 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| c-2 b6 | c-3 b6 | c-2 ff | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@voice 2 p8w5v
| c-2 b6 | c-3 b6 | === .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | === .. | ... .. | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | c-3 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@tempo 12
| === .. | c-3 b6 | ... .. | c-4 6d
| ... .. | === .. | ... .. | d-4 6d
@voice 3 p8w6d
| ... .. | e-3 b6 | c-3 b6 | e-4 6d
| ... .. | e-3 b6 | === .. | d-4 6d
| ... .. | === .. | ... .. | e-4 6d
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | d-4 6d
| ... .. | f-3 b6 | === .. | c-4 6d
| ... .. | === .. | ... .. | d-4 6d
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | g-3 b6 | c-2 ff | === ..
@voice 2 p8w5v
| ... .. | g-3 b6 | === .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
@voice 3 p8w6d
| ... .. | g-3 b6 | c-3 b6 | ... ..
| ... .. | g-3 b6 | === .. | ... ..
| ... .. | g-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
@voice 3 p8w0d
| ... .. | d-3 b6 | c-2 ff | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
@voice 3 p8w6d
| ... .. | d-3 b6 | c-3 b6 | ... ..
| ... .. | d-3 b6 | === .. | ... ..
| ... .. | d-3 b6 | ... .. | ... ..
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | e-3 b6 | === .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | f-3 b6 | c-2 b6 | ... ..
@voice 2 p8w5v
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
@voice 3 p8w6d
| ... .. | f-3 b6 | c-3 ff | ... ..
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | f-3 b6 | ... .. | ... ..
| ... .. | e-3 b6 | ... .. | ... ..
| ... .. | a-2 b6 | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| ... .. | c-3 b6 | c-2 ff | ... ..
@voice 2 p8w5v
| ... .. | c-3 b6 | === .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
| ... .. | c-3 b6 | ... .. | ... ..
@voice 2 p8w5sl
| ... .. | c-3 b6 | ... .. | ... ..
@voice 2 p8w5v
@voice 3 p8w6d
| ... .. | f-3 b6 | c-3 b6 | ... ..
| ... .. | f-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 3 p8w3d
| ... .. | g-3 b6 | c-3 b6 | ... ..
| ... .. | g-3 b6 | === .. | ... ..
| ... .. | === .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| d-2 b6 | d-3 b6 | c-2 ff | f-4 6d
@voice 2 p8w5v
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| f-2 b6 | === .. | ... .. | d-4 6d
| e-2 b6 | d-3 b6 | ... .. | e-4 6d
@voice 2 p8w5
| f-2 b6 | d-3 b6 | ... .. | f-4 6d
| e-2 b6 | === .. | ... .. | e-4 6d
@voice 2 p8w5v
@voice 3 p8w6d
| d-2 b6 | d-3 b6 | c-3 b6 | f-4 6d
| d-2 b6 | d-3 b6 | === .. | e-4 6d
@tempo 3
@voice 1 p8w5
| d-2 b6 | === .. | ... .. | d-4 6d
| d-2 b6 | ... .. | ... .. | ... ..
| d-2 b6 | ... .. | ... .. | ... ..
| d-2 b6 | ... .. | ... .. | ... ..
@tempo 12
@voice 1 p8w5v
| d-2 b6 | f-3 b6 | ... .. | e-4 6d
| d-2 b6 | e-3 b6 | ... .. | f-4 6d
@voice 1 p8w5f
| d-2 b6 | c-3 b6 | ... .. | e-4 6d
@voice 3 p8w0d
| === .. | d-3 b6 | c-2 ff | f-4 6d
@voice 1 p8w5v
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| d-2 b6 | === .. | ... .. | d-4 6d
| f-2 b6 | d-3 b6 | ... .. | e-4 6d
| e-2 b6 | d-3 b6 | ... .. | f-4 6d
| f-2 b6 | === .. | ... .. | e-4 6d
@voice 3 p8w6d
| e-2 b6 | d-3 b6 | c-3 b6 | f-4 6d
| d-2 b6 | d-3 b6 | === .. | e-4 6d
| d-2 b6 | === .. | ... .. | d-4 6d
@voice 3 p8w3d
| d-2 b6 | f-3 b6 | c-3 b6 | e-4 6d
| d-2 b6 | e-3 b6 | === .. | f-4 6d
| d-2 b6 | a-2 b6 | ... .. | e-4 6d
@voice 1 p8w5
@voice 2 p8w5
@voice 3 p8w0d
| c-2 b6 | c-3 b6 | c-2 b6 | e-4 6d
@voice 1 p8w5v
@voice 2 p8w5v
| c-2 b6 | c-3 b6 | === .. | d-4 6d
| c-2 b6 | === .. | ... .. | c-4 6d
| c-2 b6 | c-3 b6 | ... .. | d-4 6d
| c-2 b6 | c-3 b6 | ... .. | e-4 6d
| c-2 b6 | === .. | ... .. | d-4 6d
@voice 3 p8w6d
| c-2 b6 | c-3 b6 | c-3 ff | e-4 6d
| c-2 b6 | c-3 b6 | === .. | d-4 6d
@tempo 6
| c-2 b6 | c-3 b6 | ... .. | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | f-3 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | e-3 b6 | ... .. | c-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | a-2 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@voice 2 p8w5
@voice 3 p8w0d
| c-2 b6 | c-3 b6 | c-2 ff | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@voice 2 p8w5v
| c-2 b6 | c-3 b6 | === .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | === .. | ... .. | e-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
| c-2 b6 | c-3 b6 | ... .. | d-4 6d
| c-2 b6 | ... .. | ... .. | ... ..
@tempo 12
| === .. | c-3 b6 | ... .. | c-4 6d
| ... .. | === .. | ... .. | d-4 6d
@voice 3 p8w6d
| ... .. | e-3 b6 | c-3 b6 | e-4 6d
| ... .. | e-3 b6 | === .. | d-4 6d
| ... .. | === .. | ... .. | e-4 6d
@voice 3 p8w3d
| ... .. | f-3 b6 | c-3 b6 | d-4 6d
| ... .. | f-3 b6 | === .. | c-4 6d
| ... .. | === .. | ... .. | d-4 6d
@tempo 1
| ... .. | ... .. | ... .. | === ..
@pop
]]

-- ===== pico-8 compatibility layer =====

gfx.win(128, 128)
gfx.border(0)
gfx.fg(6)
gfx.bg(0)
sys.title("reverse raid")

local bit = bit
local SPRH = 64

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
  local items, n = {}, 0
  t = t or {}
  local v = t[1]
  while v ~= nil do
    n = n + 1
    items[n] = v
    v = t[n + 1]
  end
  local i = 0
  return function() i = i + 1 return items[i] end
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

snd.voices(__voices__)
mixer.reserve(1) -- engine
synth.on(1, true)
synth.vol(1, 0.5)
snd.apply(1, 'eng')

local chans = {}
local music_id

function audio.sfx(n)
  if not n or n < 0 then return end
  if n == 1 then -- engine hack
    synth.change(1, 0, synth.NOTE_ON, 340)
    return
  end
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
--reverse raid
--ny hugeping
local exp={}
local parts={}
local las={}
local last_gate=15
local lvl_h=3000

function ship_crash()
  ship.crash=ship.h
  if ship.h>0 then
    ship.crash=ship.crash+0.1
  elseif ship.h<0 then
    ship.crash=ship.crash-0.1
  end
end
function zap(v)
  v.f=nil
  v.d=nil
end
function oini(v,f,d)
    v.f=f
    v.d=d
end
local save_seed
local hiscore=0
local max_gw=0
local handl=0.03
local frict=0.9
local frictv=0.99
local gravity=0.01
local fuelr=0.0006
local r16=12
local gameover=false
local r8=12
local explode=false
local gates={}
local theend=false
local yy=-120
local cam_y=-200
local tm=0
local lives=5
local title=true

local pals={
65531.5,
65275.5,
56955.5,
24155.5,
23130.5,
22610.5,
20560.5,
4160.5,
64.5,
0.5,
}
--[[
function irnd16()
  local t=bit.bxor(bit.bxor(bit.bxor(bit.bxor(flr(r16),flr(bit.rshift(r16,14))),flr(bit.rshift(r16,13))),flr(bit.rshift(r16,11))),1)
  r16=bit.band(bit.rshift(r16,1),0x7fff)
  r16=bit.bor(r16,bit.lshift(t,15))
  return bit.band(r16,0xffff)
end
--]]
function rnd16()
  local t=bit.bxor(bit.bxor(bit.bxor(bit.bxor(flr(bit.rshift(r16,15)),flr(bit.rshift(r16,13))),flr(bit.rshift(r16,12))),flr(bit.rshift(r16,10))),1)
  r16=bit.band(bit.lshift(r16,1),0xffff)
  r16=bit.bor(r16,bit.band(t,1))
  return bit.band(r16,0xffff)
end
--[[
function irnd8()
  local t=bit.bxor(bit.bxor(bit.bxor(flr(bit.rshift(r8,6)),flr(bit.rshift(r8,5))),flr(bit.rshift(r8,4))),r8)
  r8=bit.band(bit.rshift(r8,1),0xff)
  r8=bit.bor(r8,bit.lshift(bit.band(t,1),7))
  return r8
end
--]]
function rnd8()
  local t=bit.bxor(bit.bxor(bit.bxor(flr(bit.rshift(r8,7)),flr(bit.rshift(r8,5))),flr(bit.rshift(r8,4))),flr(bit.rshift(r8,3)))
  r8=bit.band(bit.lshift(r8,1),0xff)
  r8=bit.bor(r8,bit.band(t,1))
  return r8
end
--[[
function rnd16p(v)
  local s=r16
  r16=v
  irnd16()
  r16=s
end
--]]
local lvl={}

function lnorm(cur,prev)
  if not prev then
    return
  end
  if prev.l<cur.l then
    cur.lspr=3 -- \
  elseif prev.l>cur.l then
    cur.lspr=4 -- /
    if prev.lspr==1 then
      prev.lspr=4 -- /
    end
  end
  if prev.lspr==3 and cur.lspr==4 then
    prev.lspr=2 -- >
  end
  if prev.lspr==4 and cur.l>=prev.l then
    prev.lspr=5 -- <
  end
end

function rnorm(cur,prev)
  if not prev then
    return
  end
  local ncur={l=cur.r,lspr=cur.rspr}
  local nprev={l=prev.r,lspr=prev.rspr}
  lnorm(ncur,nprev)
  cur.rspr=ncur.lspr
  prev.rspr=nprev.lspr
end
local started=false
function restart(seed)
  exp={}
  parts={}
  las={}

  gameover=false
  theend=false
  target=0
  mklevel(16,16,lvl_h,seed)
  ship={score=0,dshot=0,f=1,x=64,y=-110,g=0,v=0,h=0,t=0,tx=0}
  yy,cam_y=ship.y,ship.y
  cam()
  cam_y=yy
  mksnap(0)
  started=true
end
function _init()
  music(0,2000)
  if cartdata("hgpgrevraid") then
    max_gw=dget(0) or 0
--    max_gw=last_gate
    hiscore=dget(1) or 0
    save_seed=dget(2)
    if save_seed==0 then save_seed=false  end
  end
  fadeout(function()
    restart(save_seed)
  end)
--  ship.y=1920*8
--  restart()
end

function new(v)
  local pos=v.c%(14-(v.r+v.l+(v.land or 0)))
  for i=1,#v.spr do
    if v.spr[i]==0 then
      pos=pos-1
      if pos<=0 and i>1 and v.spr[i+1]==0 and v.spr[i-1]==0 then
        v.pos=(i-1)*8
        return true
      end
    end
  end
end

function d_mine(v)
  local x,y=tos(v.pos,v.yy)
  spr(32+flr(tm/16)%2,x-4,y-4,1,1,v.dir>0)
end
function lasd()
  for l in all(las) do
    local x,y=tos(l.x,l.y)
    if l.dy~=0 then
      spr(36+flr(tm/8)%2,x-4,y-4)
    else
      spr(34+flr(tm/8)%2,x-4,y-4)
    end
  end
end
function lasm()
  local nlas={}
  for l in all(las) do
    l.x=l.x+l.dx
    l.y=l.y+l.dy
    local _,y=tos(l.x,l.y)
    if y>128+16 or y<-16 then
      l.v.shot=false
    elseif not mmcol(l.x,l.y) then
      add(nlas,l)
    elseif fget(mmcol(l.x,l.y),0) then
      add(nlas,l)
    else
      l.v.shot=false
      sfx(6)
      expa(l.x,l.y,4,l.v)
    end
  end
  las=nlas
end

function ecol(x,y,w,h,v)
  if v and v.nc then return end
  for e in all(exp) do
    local d=((x-e.x)^2+(y-e.y)^2)^0.5
    if v~=e.v and e.r>0 and d<e.cr+(w+h)/2 then
      return true
    end
  end
end
function expd()
  for e in all(exp) do
    local x,y=tos(e.x,e.y)
    if e.r>0 then
      circfill(x,y,e.cr,15)
    else
      circfill(x,y,-e.r,15)
      circfill(x+1,y,e.cr,0)
    end
  end
end

local smk={}
function smkm()
  local nsmk={}
  for s in all(smk) do
    s.cr=s.cr+0.2
    s.y=s.y-rnd(1)
    if s.cr<s.r then
      add(nsmk,s)
    end
  end
  smk=nsmk
end

function smkd()
  for s in all(smk) do
    local x,y=tos(s.x,s.y)
    fillp(42405.5)
    circfill(x,y,s.cr,5)
    fillp()
  end
end

function smka(x,y,r)
  add(smk,{x=x,y=y,cr=0,r=r})
end

function maxexp()
  local me=-1
  for e in all(exp) do
    if e.r>0 and e.y+e.r>me then me=e.y+e.r end
  end
  if me<0 then return false end
  return flr(me/8)
end

function expm()
  local nexp={}
  for e in all(exp) do
    if e.r>0 then
      e.cr=e.cr+1
      if e.cr>=e.r then
        e.r=-e.r
        e.cr=0
      end
      add(nexp,e)
    else
      e.cr=e.cr+1
      if e.cr<=-e.r then
        add(nexp,e)
      end
    end
  end
  exp=nexp
end

function expa(x,y,r,v)
  add(exp,{x=x,y=y,r=r,cr=0,v=v})
end

function lshot(v,x,y,dx)
  v.shot=true
  add(las,{x=x+2*dx,v=v,y=y,dx=dx,dy=0})
end
function lshoty(v,x,y,dy)
  v.shot=true
  add(las,{x=x,v=v,y=y+dy*4,dy=dy,dx=0})
end

function lcol(x,y,w,h,v)
  for l in all(las) do
    if l.v~=v and l.x>=x-w and l.x-1<x+w and
      l.y>=y-h and l.y<y+h then
      del(las,l)
      l.v.shot=false
      return true
    end
  end
end

function pcol(x,y,w,h,v)
  for l in all(parts) do
    if l.x>=x-w and l.x<x+w and
      l.y>=y-h and l.y<y+h then
      del(parts,l)
      return true
    end
  end
end

function hit(x,y,xx,yy,ww,hh,dx,dy)
  dx=dx or 0
  dy=dy or 0
  if x>=xx+dx-ww and x<xx+dx+ww and
    y>=yy+dy-hh and y<yy+dy+hh then
    return true
  end
end

function scorea(d)
  local os=ship.score
  ship.score=ship.score+d or 5
  if flr(ship.score/100)~=flr(os/100) then
    lives=lives+1
    sfx(5)
  end
  if ship.score>=hiscore then
    if os<hiscore then
      sfx(8)
    end
    hiscore=ship.score
    dset(1,hiscore)
  end
end

function f_hit(v,dx,dy)
  dx=dx or 0
  dy=dy or 0
  if hit(v.pos+dx,v.yy+dy,ship.x,ship.y,8,4) then
    zap(v)
    sfx(2)
    scorea(v.score)
    expa(v.pos,v.yy,8,v)
    ship_crash()
  end
end

function f_gaub(v)
  local x=v.pos+v.dir*0.1
  if mmcol(x+v.dir*4,v.yy) then
    v.dir=-v.dir
  else
    if tm%8==1 then
      v.step=not v.step
    end
    if mmcol(x,v.yy+4) then
      v.pos=x
    end
  end
  if not ship.crash and v.yy>ship.y and not v.shot then
    lshoty(v,v.pos+1,v.yy-2,-1)
    sfx(7)
  end
  f_hit(v)
  f_lcol(v,4,4,0,0,4)
end

function d_gaub(v)
  local x,y=tos(v.pos-4,v.yy-4)
  spr(56+(v.step and 0 or 1),x,y)
end

function f_tank(v)
  if not v.started then
    if abs(ship.y-v.yy)<v.dist then
      v.started=true
    end
    return
  end
  if v.delay>0 then
    v.delay=v.delay-1
  end
  local x=v.pos+v.dir*0.1
  if x<0 or x>128 or mmcol(x+v.dir*4,v.yy) then
    v.pos=x
    if tm%8==1 then
      v.step=not v.step
    end
  else
    if not ship.crash and not v.shot and v.delay<=0 then
      lshot(v,v.pos+4*v.dir,v.yy,v.dir)
      v.delay=120
      sfx(7)
    end
  end
  if v.pos>-8 and v.pos<132 then
    f_hit(v)
    f_lcol(v,4,4,0,0,6)
  end
end

function d_tank(v)
  local x,y=tos(v.pos-4,v.yy-4)
  spr(58+(v.step and 1 or 0),x,y,1,1,v.dir<0)
end

function f_mine(v)
  v.m=v.m+0.01
  local xx=v.pos
  if v.started then
    if agate(v,3) then
      xx=xx+v.dir*0.3
    end
  else
    if abs(ship.y-v.yy)>8 then
      v.started=abs(ship.y-v.yy)<v.dist
    end
  end
  if mmcol(xx+v.dir*4,v.yy) then
    v.dir=-v.dir
  else
    v.pos=xx
  end
  v.yy=v.y*8+4+sin(v.m)*4,1
  if v.started and not v.shot and not ship.crash and ship.y>v.yy-16 and ship.y<v.yy+16 then
    if sgn(ship.x-v.pos)==sgn(v.dir) then
      if agate(v,7) then
        sfx(7)
        lshot(v,v.pos,v.yy,
        (ship.x<v.pos) and -1 or 1)
      end
    end
  end
  f_hit(v)
  f_lcol(v,4,4,0,0,4)
end

function agate(v,n)
  return flr(v.y/128)>=n
end

function n_gaub(v)
  if not agate(v,5) then return end
  if not v then return end
  if new(v) then
    v.nam="gaub"
    v.score=3
    v.yy=v.y*8+6
    v.pos=v.pos+4
    v.dir=(v.c%2==1) and -1 or 1
    oini(v,f_gaub,d_gaub)
  end
end
function n_mine(v)
  if not agate(v,2) then return end
  if v.y<16 then return end
  if new(v) then
    v.nam="mine"
    v.score=2
    v.m=0
    v.started=false
    v.dist=(v.c%15)*8
    v.pos=v.pos+4
    v.yy=v.y*8+4
    v.dir=(v.c%2==1) and 1 or -1
    oini(v,f_mine,d_mine)
  end
end

function f_lcol(v,w,h,dx,dy,rr)
  if lcol(v.pos+(dx or 0),v.yy+(dy or 0),w,h,v)
    or pcol(v.pos+(dx or 0),v.yy+(dy or 0),w,h)
    or ecol(v.pos+(dx or 0),v.yy+(dy or 0),w,h,v)
    then
    zap(v)
    sfx(2)
    expa(v.pos,v.yy,rr or h,v)
    scorea(v.score)
  end
end

function d_fuel(v)
  local x,y=tos(v.pos,v.yy)
  spr(38+flr(tm/8)%2,x-4,y-8,1,2)
end

function f_fuel(v)
  f_lcol(v,4,8)
  local n=lvl[v.y+2]
  if v.f and n and n.laser then
    local x,e=n.pos+4,n.stop
    if x>e then
      x,e=e,x
    end
    if v.pos>=x and v.pos<=e then
      zap(v)
      expa(v.pos,v.yy,8)
    end
  end
  if not ship.crash and (hit(v.pos,v.yy-4,ship.x,
    ship.y,8,4) or hit(v.pos,v.yy+4,ship.x,
    ship.y,8,4)) then
    ship.f=ship.f+0.01
    if ship.f>1 then ship.f=1 end
    if ship.f<1 then
      if tm%8==1 then
        sfx(3)
      end
    end
  end
end

local snap={}

function mksnap(g)
  if ship.crash then
    return
  end
  if g>max_gw then
    max_gw=g
    dset(0,g)
  end
  ship.gw=g
  snap={}
  for k,v in pairs(ship) do
    snap[k]=v
  end
--  printh("mksnap "..tostr(g))
end
function rgate(g,set)
  for i=g.l+1,14-g.r do
    g.spr[i+1]=set and 50 or 0
    if set then add(g.brk,i+1) end
  end
  g.f=set and f_gate
  g.d=set and d_gate

  if g.y>0 then
    n_gaub(lvl[g.y])
    if not set then
      zap(lvl[g.y])
    end
  end
end
function restore(gw)
  ship={}
  if not gw then
    mklevel(16,16,lvl_h,save_seed)
  else
    for g in all(gates) do
      rgate(g,true)
    end
  end
  for k,v in pairs(snap) do
    ship[k]=v
  end
  if gw then ship.gw=gw end
  ship.v=0
  ship.h=0
  ship.f=1
  target=0
  local g=gates[ship.gw]
  if ship.gw>1 then
    ship.y=g.y*8-- -12
  elseif ship.gw==1 then
    ship.y=-64
  elseif ship.gw==0 then
    ship.y=-110
  end
  if g and ship.gw>=g.nr then
    rgate(g)
  end
  ship.x=64
  ship.shot=false
  camera()
  yy,cam_y=ship.y,ship.y
  cam()
  cam_y=yy
end

function f_bgun(v)
--  if not ship.crash then
--    lshoty(v,v.pos+1,v.yy-2,-1)
--  end
end

function f_brk(v,k)
  local s=v.spr[k]
  if s==0 then
    del(v.brk,k)
    return
  end
  local tv={nam="brk",
    pos=k*8-4,
    yy=v.y*8+4}
  tv.d=true
  tv.nc=(s==112)
  tv.score=(s==112)and 5 or 1;
  f_lcol(tv,4,4,0,0,6)
  if not tv.d then
    v.spr[k]=0
    del(v.brk,k)
    if s==112 then
      if not explode then explode=10 end
      target=target+1
    elseif v.gate then
      if not explode then explode=10 end
      mksnap(v.nr)
    end
  end
  if s==62 and tv.d then
    return f_bgun(tv)
  end
end
--[[
function f_item(v)
  local tv={pos=4,yy=v.y*8+4}
  for k,p in ipairs(lvl[v.y+1].spr) do
      if fget(p,0) then
        tv.d=true
        f_lcol(tv,4,4,0,0,6)
        if not tv.d then
          v.spr[k]=0
          if v.gate then
            if not explode then explode=8 end
            mksnap(v.nr)
          end
        end
      end
      tv.pos=tv.pos+8
  end
end
--]]
function f_laser(v)
  if not v.tm then
    v.tm=0
  end
  v.tm=v.tm+1
  if v.tm>flr(v.tmmax/2) then
    v.laser=true
    if v.tm>v.tmmax then
      v.laser=false
      v.tm=0
    end
  end
  f_lcol(v,4,4,4,4)
  f_hit(v,4,4)
  if v.laser then
    sfx(4)
    if mm(v.stop+v.dir*4,v.yy)==0 then
      n_laser(v)
    end
    local x,e=v.pos+4,v.stop
    if v.pos>v.stop then
      x,e=e,x
    end
    if ship.x>x and ship.x<e and
      ship.y-4<v.yy+3 and ship.y+4>v.yy+3 then
      if not ship.crash then
        sfx(2)
        expa(ship.x,ship.y,8,ship)
      end
      ship_crash()
    end
  end
end

function d_laser(v)
  local x,y=tos(v.pos,v.yy)
  spr(48+flr(tm/8)%2,x,y,1,1,v.dir<0)
  if v.laser then
    if v.dir<0 then
      x=x-7
    end
    line(x+7,y+3+tm%2,v.stop,y+3+tm%2,(flr(tm/4)%2==1) and 12 or 7)
    if tm%7==1 then
      sparka(v.stop,v.yy+3)
    end
  end
end

function n_laser(v)
  local p={}
  for i=1,#v.spr do
    local s=v.spr[i]
    if s==17 or s==1 then
      add(p,{s,(i-1)*8})
    end
  end
  p=p[v.c%#p+1]
  if not p then return end
  if p[1]==17 then
    v.pos=p[2]-8
    v.dir=-1
  elseif p[1]==1 then
    v.pos=p[2]+8
    v.dir=1
  end
  local x=v.pos
  v.yy=v.y*8
  while true do
    x=x+v.dir
    if mmcol(x,v.yy+4) or x>128 or x<0 then
      v.stop=x-v.dir
      break
    end
  end
  v.nam="laser"
  v.score=3
  oini(v,f_laser,d_laser)
  v.tmmax=240 -- s+v.c%128
end

function n_tank(v)
  if not agate(v,9) then return end
  v.nam="tank"
  v.score=4
  v.delay=0
  v.dist=(v.c%15)*8
  if v.c%2==1 then
    v.dir=1
    v.pos=-8
  else
    v.dir=-1
    v.pos=136
  end
  v.yy=v.y*8+4
  oini(v,f_tank,d_tank)
end

function n_rock(v)
  if not agate(v,12) then return end
  v.nam="rocket"
  v.score=3
  v.dist=(v.c%15)*8
  if v.c%2==1 then
    v.dir=1
    v.pos=-8
  else
    v.dir=-1
    v.pos=136
  end
  v.yy=v.y*8+4
  oini(v,f_rock,d_rock)
end

function f_rock(v)
  if not v.started then
    if abs(ship.y-v.yy)<v.dist then
      v.started=true
    end
    return
  end
  v.pos=v.pos+v.dir*1
  if v.pos>256 then v.pos=-7 end
  if v.pos<-128 then v.pos=136 end
  if v.pos>-8 and v.pos<132 then
    f_hit(v)
    f_lcol(v,4,2,0,0,6)
  end
end

function d_rock(v)
  local x,y=tos(v.pos-4,v.yy-4)
  spr(60+flr(tm/4)%2,x,y,1,1,v.dir<0)
  if v.dir>0 then
    spr(29+flr(tm/4)%2,x-8,y,1,1,true)
  else
    spr(29+flr(tm/4)%2,x+8,y,1,1)
  end
end

function n_fuel(v)
  if v.y<32 then return end
  if new(v) then
    v.pos=v.pos+4
    v.nam="fuel"
    v.score=10
    v.yy=v.y*8+8
    if mm(v.pos,v.yy)==0 and
      mm(v.pos,v.yy+8)==0 then
      oini(v,f_fuel,d_fuel)
    end
  end
end

function mklevel(w,h,hh,seed)
  save_seed=seed
  dset(2,save_seed)
  seed=seed or 12
  r16,r8=seed,seed
  lvl={}
  local l,r=4,12
  local t=1
  local cland=0
  local land=0
  local dist=0
  local gate_nr=0
  gates={}
  for y=1,hh do
    dist=dist+1
    if t~=5 and t~=0 then

    if dist>128 and gate_nr<last_gate-1 then
      t=0
      cland=0
    elseif y%h==0 and t~=5 then
      t=rnd8()%3+1
      cland=0
    end
    end
    local pl,pr,pland=l,r,land
    local c=abs(rnd16())
    local cl=bit.band(bit.rshift(c,4),0xf)
    local cr=bit.band(c,0xf)
    local l1,r1
    if t==0 then
      cl=0
      cl=4+cl
      cr=w-1-cl
    elseif t==1 then
      cl=cl%6
      cr=w-1-cl
    elseif t==2 then
      cl=cl-cr
      cr=cl+cr
    elseif t==3 then
      cland=(cr+cl)%4+1
      cl=cl%3
      cr=cr%3
      cr=w-1-cr
    elseif t==5 then
      cl=0
      cr=w-1
    end
    local free=r-l-1
    if cland>pland and free>9 then
      land=land+1
    elseif cland<pland or free<=7 then
      land=land-1
    end
    if cland>0 and land==0 then
      land=1
    end
    if cl>pl then
      l=l+1
    elseif cl<pl then
      l=l-1
    end
    if cr<pr then
      r=r-1
    elseif cr>pr then
      r=r+1
    end
    if l<=0 then l=0 end
    if r>=w-1 then r=w-1 end
    while abs(r-l)<4 do
      l=l-1
      r=r+1
      if l<=0 then l=0 end
      if r>=w-1 then r=w-1 end
    end
    local cur={t=t,l=l,r=w-r-1,c=c}
    if y==1 then cur.gate=true end
    if land>0 then
--      cur.lx=(w-(cur.l-1+cur.r))\2
      cur.lx=cur.l+ceil((free)/2) --todo
      cur.land=land
    end
--    printh(tostr(l)..tostr(" ")..tostr(r))
    if l>=4 and r<=11 and free>3
      and t==0 then
      if dist>128+7 then
        dist=-6
        cur.gate=true
        gate_nr=gate_nr+1
--        printh("start"..gate_nr)
      end
--      printh("dist"..dist.." "..y)
      if dist==0 then
--        printh(gate_nr.." "..y)
        t=1
        if gate_nr>=last_gate-1 then
          t=5
        end
      end
    end
    add(lvl,cur)
    if t==5 and dist>32 then
      hh=y
      break
    end
  end
--  printh("hh="..hh)

  local prev
  for y=1,#lvl do
    local cur=lvl[y]
    cur.lspr,cur.rspr=1,1
    lnorm(cur,prev)
    rnorm(cur,prev)
    cur.spr={}
    prev=cur
  end
-- tiles
  prev=false
  for y=1,#lvl do
    local cur=lvl[y]
    for x=1,w do
      if x-1<cur.l or x>w-cur.r then
        cur.spr[x]=7
      elseif x-1==cur.l then
        cur.spr[x]=cur.lspr
      elseif x==w-cur.r then
        cur.spr[x]=cur.rspr+16
      else
        cur.spr[x]=0
      end
    end

    if cur.land then
      local xc=cur.lx-flr(cur.land/2)
      local xe=xc+cur.land-1
      local pxc,pxe
      cur.xc,cur.xe=xc,xe
      if prev and prev.land then
        pxc,pxe=prev.xc,prev.xe
        while pxe>xe+1 do
          xe=xe+1
          cur.land=cur.land+1
        end
        while pxc<xc-1 do
          xc=xc-1
          cur.land=cur.land+1
        end
        while pxe<xe-1 do
          xe=xe-1
          cur.land=cur.land-1
        end
        while pxc>xc+1 do
          xc=xc+1
          cur.land=cur.land-1
        end
        cur.xc,cur.xe=xc,xe
      end

      for i=cur.xc,cur.xe do
        local pp=prev.spr[i+1]
        if cur.xc==cur.xe then
          cur.spr[i+1]=8
        elseif i==cur.xc then
          cur.spr[i+1]=17
        elseif i==cur.xe then
          cur.spr[i+1]=1
        else
          cur.spr[i+1]=7
        end
      end

      local pc,pe,px,cc,ce,pa,pb

      if prev then
        pc=prev.spr[xc+1]
        pe=prev.spr[xe+1]
        pa=prev.spr[xc]
        pb=prev.spr[xe+2]
        if prev.land then
          px=prev.spr[prev.xc+1]
        end
      end

      if cur.land==1 then
        if pc==0 then
          if px==6 then
            prev.spr[prev.xc+1]=23
          elseif px~=nil then
            prev.spr[prev.xc+1]=22
          end
          cur.spr[xc+1]=6
        end
      end

      cc=cur.spr[xc+1]
      ce=cur.spr[xe+1]

      if pc==0 and cc==17 then
        cur.spr[xc+1]=19
      end
      if pa==19 then
        prev.spr[xc]=18
      end
      if pa==17 and prev.land~=1 then
        prev.spr[xc]=20
      end

      if pe==0 and ce==1 then
        cur.spr[xe+1]=3
      end
      if pb==3 then
        prev.spr[xe+2]=2
      end
--      printh(tostr(y).." "..tostr(cur.land).." "..tostr(pa).." "..tostr(pb))
      if pb==1 and prev.land~=1 then
        prev.spr[xe+2]=4
      end
    elseif prev and prev.land then
      if prev.land>1 then
        cur.spr[prev.xc+1]=22
        if prev.spr[prev.xe+1]==3 then
          prev.spr[prev.xe+1]=2
        else
          prev.spr[prev.xe+1]=4
        end
      else
        if prev.spr[prev.xc+1]==6 then
          prev.spr[prev.xc+1]=23
        else
          prev.spr[prev.xc+1]=22
        end
      end
    end
    if cur.gate then
      for i=cur.l+1,14-cur.r do
        cur.spr[i+1]=50
    --    curoitem
      end
      add(gates,cur)
      cur.nr=#gates
    end
    prev=cur
  end
  lvl[1].spr[lvl[1].l+1]=1
  lvl[1].spr[16-lvl[1].r]=17
  for y=1,#lvl do
    local v=lvl[y]
    v.y=y-1
    v.brk={}
    for k,c in ipairs(v.spr) do
      if fget(c,0) then
        add(v.brk,k)
      end
    end
    if v.gate and y>1 then
      n_gaub(lvl[y-1])
    end
    if v.t~=0 and not v.gate then
      local r=bit.band(bit.rshift(v.c,7),0xff)
      if r%16==1 then
        n_mine(v)
      elseif r%22==7 then
        n_fuel(v)
      elseif r%4==1 then
        n_laser(v)
      elseif r%17==1 then
        n_tank(v)
      elseif r%15==1 then
        n_rock(v)
      end
    end
  end
  for y=-16,0 do
    lvl[y]={spr={},l=0,r=0}
    for x=1,16 do
      lvl[y].spr[x]=0
    end
  end

  lvl[hh].spr[12]=62
  lvl[hh].spr[5]=62
  add(lvl[hh].brk,12)
  add(lvl[hh].brk,5)

  for y=hh+1,hh+24 do
    local l={spr={},l=0,r=0,y=y-1,brk={}}
    lvl[y]=l
    for x=1,16 do
      if y<hh+8 then
        if x==5 and y<hh+5 then l.spr[x]=5
        elseif x==12 then l.spr[x]=21
        elseif y>hh+4 and x<=5 then
          l.spr[x]=0
          if x==5 then
            l.spr[x]=114
            add(l.brk,x)
          end
        else
          l.spr[x]=7
        end
      elseif y==hh+8 and
        x<12 then
        l.spr[x]=24
      else
        l.spr[x]=7
      end
      if x>5 and x<12 and y<hh+8 then
        l.spr[x]=112
        add(l.brk,x)
      elseif x>1 and x<16 and y==hh+1 then
        l.spr[x]=24
        l.spr[5]=1
        l.spr[12]=17
      end
    end
  end
  zap(lvl[hh-1])
  zap(lvl[hh-2])
  n_laser(lvl[hh-3])
  n_laser(lvl[hh-4])
  local l=lvl[hh+8]
  l.spr[11]=97
  for i=12,16 do
    l.spr[i]=98
  end
--printh(#gates)
end
local thrust=0
function cam()
  local d=abs(cam_y-yy)
  local v=cos(0.25+ship.v*0.25)
  if ship.t then
    if thrust<0 then thrust=0 end
    thrust=thrust+1
  else
    if thrust>0 then thrust=0 end
    thrust=thrust-1
  end
  if yy~=cam_y then
    if d>1 then
      if abs(thrust)<30 then
        d=clamp(d/8,0,1)
      else
        d=1
      end
    end
    if cam_y>yy then
      yy=yy+d
    else
      yy=yy-d
    end
    if yy<-120 then yy=-120 end
  end
  if not ship.explode then
    if ship.crash then
      cam_y=(ship.y-48)
    else
      cam_y=(ship.y-48)-v*32
    end
  end
end
function clamp(v,m,x)
  if v<m then v=m end
  if v>x then v=x end
  return v
end

function mm(x,y)
  if x<0 or x>=128 or y<0 then
    return
  end
  local v=lvl[flr(y/8)+1]
  if not v then return end
  return v.spr[flr(x/8)+1]
end

function mmcol(x,y)
  local c=mm(x,y)
  if not c or c==0 then return end
  local cc=sget((c%16)*8+x%8,flr(c/16)*8+y%8)
  if cc==0 then
    return
  end
  return c
end

function shipcol()
  local x,y=ship.x,ship.y
  local c=mmcol(x,y) or
    mmcol(x+7,y) or
    mmcol(x-6,y) or
   mmcol(x+7,y+3) or
    mmcol(x-6,y+3) or
    mmcol(x,y+3) or
    mmcol(x,y-3)
  if c and not ship.crash then
    sfx(2)
    expa(ship.x,ship.y,8,ship)
    ship_crash()
  end
end

function f_end()
  theend=0
  ship.h=rnd(1)
  ship.v=rnd(1)
  ship.y=110
end

function endm()
  ship.x=64+cos(ship.h)*4
  ship.h=ship.h+rnd(0.01)
  ship.v=ship.v+rnd(0.005)
  if theend~=true and theend>128 then
    yy=yy+1
    cam_y=yy
    ship.y=ship.y-1
    if theend==129 then
      sfx(11)
    end
  else
    cam_y=ship.y-100+4*sin(ship.v)
    yy=cam_y
    ship.t=true
    ship.tx=0
    sfx(1)
  end
  if theend==true then theend=0 end
  if theend<500 then theend=theend+1 end
end

function shipm()
  if (gameover or (theend and theend>200)) and (btnp(4) or btnp(5)) then
    fadeout(function()
      if not theend then
        music(0,2000)
      end
      lives=5
      restart(save_seed)
      title=true
    end)
    return
  end
  if theend then
    endm()
    return
  end
  if title and not fade then
    if btnp(0) then
      ship.gw=ship.gw-1
      if ship.gw<0 then
        ship.gw=0
      else
        restore(ship.gw)
        mksnap(ship.gw)
        sfx(9)
      end
    elseif btnp(1) then
      ship.gw=ship.gw+1
      if ship.gw>max_gw then
        ship.gw=max_gw
      else
        restore(ship.gw)
        mksnap(ship.gw)
        sfx(9)
      end
    elseif btnp(2) and save_seed then
      sfx(10)
      fadeout(restart)
    elseif btnp(3) then
      sfx(10)
      fadeout(function()
          restart(flr(rnd(16384)))
      end)
    elseif btnp(4) or btnp(5) then
      title=false
      ship.v=0
      ship.h=0
      music(-1,2000)
--[[ --hack
      fadeout(function()
        f_end()
        theend=0
      end)
--]]
    else
      ship.y=ship.y-sin(ship.v)*rnd(0.2)
      ship.x=ship.x-cos(ship.h)*rnd(0.1)
      ship.v=ship.v+rnd(0.02)
      ship.h=ship.h+rnd(0.02)
    end
    return
  end
  local y,x=ship.y,ship.x
  y=y+cos(0.25-ship.v*0.25)
  x=x+cos(0.25-ship.h*0.25)
  if ship.crash then x=x+ship.crash  end
  if not ship.crash then
    if x<0 and y>0 and target>0 then
      -- ending
      fadeout(f_end)
      ship.x=ship.x-0.5
      return
    end
    ship.x,ship.y=x,y
  else
    if not mmcol(x+6,y+2) and
      not mmcol(x-5,y+2) and
      not mmcol(x,y+2) then
      ship.x,ship.y=x,y
      if tm%10==1 and not ship.explode then
        smka(ship.x+rnd(8)-4,ship.y+rnd(8)-4,8)
      end
    else
      if not ship.explode then
        sfx(2)
        expa(ship.x,ship.y,8,ship)
        ship.explode=15
        explode=15
        partsa(ship.x,ship.y)
      end
    end
  end
  local both=btn(0) and btn(1)
  if not both and btn(0) and ship.f>0 and not ship.crash then
    if ship.h>0 then ship.h=ship.h*frict end
    ship.h=ship.h-handl
    ship.tx=-1
    ship.f=ship.f-fuelr
  elseif not both and btn(1) and ship.f>0 and not ship.crash then
    if ship.h<0 then ship.h=ship.h*frict end
    ship.h=ship.h+handl
    ship.tx=1
    ship.f=ship.f-fuelr
  else
    ship.h=ship.h*frict
    ship.tx=0
  end
  if ship.f<0.25 and tm%60==1 and not ship.crash then
    sfx(23)
  end
  if ship.dshot==0 and not ship.crash and btnp(4) then
    sfx(0)
    lshoty(ship,ship.x+1,ship.y-3,3)
    ship.dshot=20
  end
  if not ship.crash and ship.dshot>0 then ship.dshot=ship.dshot-1 end
  ship.h=clamp(ship.h,-1,1)
  if (btn(2) or btn(5) or both) and ship.f>0 and not ship.crash then
    ship.v=ship.v-handl
    ship.t=true
    ship.f=ship.f-fuelr
  else
    ship.t=false
    ship.v=ship.v*frictv
  end
  if ship.t or ship.tx~=0 then
    sfx(1)
  else
    synth.change(1, 0, synth.NOTE_OFF, 0)
  end
  if ship.f<0 then ship.f=0 end
  if ship.y<0 then
    if x<8 then ship.tx=1 ship.h=ship.h+0.2 end
    if x>=120 then ship.tx=-1 ship.h=ship.h-0.2 end
    if y<-128 then ship.t=false ship.v=0 end
  end
  if not ship.t then
    ship.v=ship.v+gravity
  end
  ship.v=ship.v+gravity
  ship.v=clamp(ship.v,-1,1)
  shipcol()
  if lcol(ship.x,ship.y,8,4) or
    ecol(ship.x,ship.y,8,4,ship) then
    expa(ship.x,ship.y,8,ship)
    sfx(2)
    ship_crash()
  end
end

function _update60()
  tm=tm+1
  if not started then
    return
  end
  if theend then
    shipm()
    cam()
    return
  end
  local me=(maxexp() or flr(yy/8))
  me=max(18,me-flr(yy/8)+1)
  for y=1,me do
    local v=lvl[y+flr(yy/8)]
    if v.f and not title then
      v:f()
    end
    for b in all(v.brk) do
      f_brk(v,b)
    end
  end
  lasm()
  expm()
  shipm()
  smkm()
  partsm()
  cam()
end
function tos(x,y)
  return x,y-yy
end

function partsm()
  local np={}
  for p in all(parts) do
    local vx,vy=cos(p.dir),sin(p.dir)
    local dy=vy+p.t*0.03
    local dx=vx
    if p.vx then
      dx=dx*p.vx
    end

    if mmcol(p.x+dx,p.y+dy) then
      if p.spark then
        if mmcol(p.x+dx,p.y) then
          vx=-vx
          p.dir=atan2(vx,vy)
        elseif mmcol(p.x,p.y+dy) then
          vy=-vy
          p.t=1
          p.dir=atan2(vx,vy)
        else
          p.l=1000
        end
      else
          sfx(6)
          expa(p.x,p.y,rnd(3)+3,p)
          p.l=1000
      end
    else
      p.x=p.x+dx
      p.y=p.y+dy
    end
    p.t=p.t+1
    p.l=p.l+1
    local x,y=tos(p.x,p.y)
    if p.l<300 and x>-8 and x<132 and y>-8 and y<132 then
      add(np,p)
    end
  end
  parts=np
end

function trnd(n)
  return flr(rnd(n))+1
end

function sparka(x,y)
  local col={8,9,10,12}
--  for i=1,rnd(6)+6 do
    add(parts,{spark=true,
    v=1,vx=0.95,x=x,
    y=y,dir=rnd(1),
    l=290,t=0,
    color=col[trnd(#col)]})
--  end
end

function partsa(x,y)
  local p={13,14,15,31,47,41,42}
  for i=1,rnd(6)+6 do
    add(parts,{v=1,
    hi=flr(rnd(2))==1,
    vi=flr(rnd(2))==1,
    x=x,y=y,dir=rnd(1),l=0,t=0,
    spr=p[(i-1)%#p+1]})
  end
end

function partsd()
  for p in all(parts) do
    if p.spark then
      local x,y=tos(p.x,p.y)
      pset(x,y,p.color)
    else
      local x,y=tos(p.x-4,p.y-4)
      spr(p.spr,x,y,1,1,p.hi,p.vi)
    end
  end
end

function shipd()
  local x,y=tos(ship.x,ship.y)
  local s=9
  local d1,d2=0,0
  if ship.explode then
    return
  end
  if type(ship.crash)=='number' then
    if ship.crash>0 then
      spr(11,x-8,y-4,2,1,true)
    elseif ship.crash<0 then
      spr(11,x-8,y-4,2,1)
    else
      spr(9,x-8,y-4,2,1)
    end
  elseif ship.tx<0 then
    d2=1
    spr(11,x-8,y-4,2,1)
  elseif ship.tx>0 then
    spr(11,x-7,y-4,2,1,true)
    d1=1
  else
    spr(9,x-8,y-4,2,1)
  end
  if ship.t then
    spr(25+(flr(tm/5)%3),x-9,y+4-d1)
    spr(25+((flr(tm/5)+1)%3),x+2,y+4-d2)
  end
  if ship.tx<0 then
    spr(29+(flr(tm/5)%2),x+7,y-2)
  end
  if ship.tx>0 then
    spr(29+(flr(tm/5)%2),x-14,y-2,1,1,true)
  end
end
function anim(c)
  local a={
    [50]={50,51,52,53};
    [62]={62,63};
    [112]={112,113},
  }
  if a[c] then
    c=a[c][flr(tm/10)%#a[c]+1]
  end
  return c
end
local fade=false
local fade_nr=0

function fadeout(cb)
  if fade then return end
  fade=1
  fade_nr=1
  fade_cb=cb
end
function fading()
  if fade then
    if fade>#pals or fade==0 then
      fade=false
      if fade_cb then fade_cb() end
      fade_cb=nil
      if fade_nr>0 then
        fillp()
        rectfill(0,0,127,127,0x00)
        fade=#pals
        fade_nr=-1
      end
    else
      fillp(pals[fade])
      rectfill(0,0,127,127,0x00)
      fillp()
    end
    if tm%5==1 then fade=fade+fade_nr end
  end
end

function hud()
  if title then
    return
  end
  if gameover then
    print("game over",48,60,flr(tm/4)%2==1 and 8 or 15)
  end
  spr(43,64-12,0,3,1)
  print("gate "..ship.gw,100,0,7)
  local fx=ceil(20*ship.f)
  line(64-11+fx,1,64-11+fx,3,10)
  if hiscore>ship.score then
    print("score "..ship.score,0,0,7)
  else
    print("score "..ship.score,0,0,flr(tm/5)%2==1 and 15 or 7)
  end
  for i=1,lives do
    if i>10 then
      break
    end
    print("♥",128-i*6,123,8)
  end
--  print(tostr(yy\8),0,0,7)
end

function endd()
  pal(14,0)
  starsd()
  if theend>200 then
    if theend==201 then
      music(0,2000)
    end
    pal()
    local x,y=0,42
    print("the end",x+50,y,12)
    y=y+10
    local pcnt=flr(target/42*100)
    x=x+16
    print("you are the brave hero!",x,y,8)
    y=y+6
    print("you destroyed "..pcnt.."% of data.",x,y,7)
    y=y+6
    print("evil kylix is defeated!",x,y)
    y=y+10
    print("thank you, pilot!",x,y)
    local sc="score "..ship.score
    print(sc,64-(flr(#sc/2))*4,0,flr(tm/5)%2==1 and 7 or 15)
    fading()
    return
  end
  local off=tm*2%8

  if theend>100 then
    off=(theend-100)*2
  end

  for y=-1,16 do
      for x=1,16 do
          spr(16,(x-1)*8,off+(y-1)*8)
      end
  end

  if theend>100 then
    map(16,0,0,-8*10+off,16,8)
    if off<200 then
      for i=1,3 do
        spr(115,(i+4)*8-flr(off/7),-16+off)
        spr(115,(i+7)*8+flr(off/7),-16+off)
      end
    end
  end

  local s=16
  for y=-1,16 do
      for x=1,16 do
          if x<5 or x>12 then
            s=7
          elseif x==5 then
            s=1
          elseif x==12 then
            s=17
          else
            s=0
          end
          if s~=0 then
            spr(s,(x-1)*8,off+(y-1)*8)
          end
      end
  end
  shipd()
--  cam()
  pal()
  fading()
end

function starsd()
    if not stars then
      stars={}
      local col={
        1,8,13,15,12,
      }
      for i=1,30 do
        add(stars,
          {x=rnd(128),
          y=rnd(128),
          c=col[trnd(#col)]})
      end
    end
    for s in all(stars) do
      pset(s.x,s.y,s.c)
      if theend and theend>180 then s.y=s.y+(s.c/8) end
      if s.y>128 then
        s.x=rnd(128)
        s.y=-rnd(16)
      end
    end
    pal(14,0)
--    spr(68,100,(y-24)*0.7,2,2)
    if not theend then
      spr(68,100,40,2,2)
    end
    pal(15,0)
end
function paint(xoff,yoff,y,col)
  if y<0 then return end
  for x=0,6*8 do
    local yy=flr(70/16)*8+y%16
    local xx=70%16*8
    local c=sget(xx+x,yy)
    if c~=0 and c~=14 then
      pset(xoff+x,yoff+y,col)
    end
  end
end

function _draw()
  if not started then
    fading()
    return
  end
  cls(0)
  if theend then
    endd()
    return
  end
  if explode then
      if explode>0 then
        camera(rnd(4)-2,rnd(4)-2)
      end
      explode=explode-1
      if explode==0 then
        camera()
      end
      if explode<-15 then
        explode=false
      end
  end
  if ship.explode then
    ship.explode=ship.explode-1
    if ship.explode<-128 then
      if lives>1 then
        fadeout(function()
          lives=lives-1
          restore()
        end)
      else
        lives=0
        gameover=true
      end
    end
  end
  if -yy<=128 then
    starsd()
    local _,y=tos(0,-4)
    pal(15,0)
    map(0,0,0,y-60,16,8)
    for x=0,15 do
      if x<=lvl[1].l or
        x>=15-lvl[1].r then
        spr(96,x*8,y-4)
      end
    end
    pal()
  end

  pal(15,0)
  for y=1,17 do
      for x=1,16 do
        if y+flr(yy/8)>0 then
          local plx=1.2
          if yy<0 then plx=1 end
          spr(16,(x-1)*8,(y-1)*8-yy/plx%8)
        end
      end
  end
  pal()
  for y=1,17 do
    local v=lvl[y+flr(yy/8)]

    for x=1,#v.spr do
      if v.spr[x]~=0 then
        local s=anim(v.spr[x])
        pal(15,0)
        spr(s,(x-1)*8,(y-1)*8-yy%8)
        pal()
      end
    end
--    spr(v.lspr,v.l*8,(y-1)*8-yy%8)
--    spr(v.rspr+16,(15-v.r)*8,(y-1)*8-yy%8)
  end
  for y=-1,17 do
    local v=lvl[y+flr(yy/8)]
    if v and v.d then
      v:d()
    end
  end
  shipd()
  lasd()
  partsd()
  expd()
  smkd()
  hud()
  if title then
    pal(14,0)
    spr(70,44,24,6,2)
    pal()
    local p=flr(tm/8)%24
    if p<16 then
      paint(44,24,p-1,12)
      paint(44,24,p,12)
    end
    print("BY hUGEPING",43,42,1)
    local x,y=0,60
    print("pilot! this is the planet",x+12,y,6)
    y=y+6
    print("of evil boltzmann brain kylix!",x+5,y)
    y=y+6
    print("destroy the main data center!",x+7,y,8)
    y=y+6
    print("it is behind 15 gates.",x+24,y,8)
    y=y+6
    print("good luck!",x+48,y,9)
    y=y+12
    print("🅾️/z start",x+48,y,flr(tm/4)%2==1 and 15 or 8)
    y=y+6
    y=y+2
    if max_gw>0 then
      print("gate ⬅️"..ship.gw.."➡️",x+48,y,15)
    end
    y=y+8
    if save_seed then
      print("⬆️ reset-next ⬇️",x+34,y,13)
    else
      print("⬇️ random world",x+36,y,13)
    end
    print("v1.2",112,122,15)
--    print("hugeping presents",32,0)
    if hiscore>0 then
      local h="hi score "..hiscore
      local x=64-#h*2
      print("hi score "..hiscore,x,0,flr(tm/5)%2==1 and 13 or 2)
    end
  end
  if save_seed then
    print("seed "..save_seed,0,122,7)
  end
  fading()
end

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
