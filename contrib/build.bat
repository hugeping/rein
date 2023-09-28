set MINGW=../../mingw64/bin
set REIN=..
set LUA=../../LuaJIT
set SDL=../../SDL2/x86_64-w64-mingw32
set CFILES=%REIN%/src/bit.c %REIN%/src/gfx.c %REIN%/src/gfx_font.c %REIN%/src/lua-compat.c %REIN%/src/main.c %REIN%/src/net.c %REIN%/src/platform.c %REIN%/src/stb_image.c %REIN%/src/stb_image_resize.c %REIN%/src/stb_truetype.c %REIN%/src/synth.c %REIN%/src/system.c %REIN%/src/thread.c %REIN%/src/utf.c %REIN%/src/zvon.c %REIN%/src/zvon_mixer.c %REIN%/src/zvon_sfx.c
"%MINGW%/gcc.exe" -Wall -O3 %CFILES% -I%LUA%/src -I%SDL%/include/SDL2 -L%LUA%/src -lluajit -L%SDL%/lib -lSDL2 -lSDL2main -lws2_32 -o %REIN%/rein.exe
