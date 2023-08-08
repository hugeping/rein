set -e
test -z "$sdl_ver" && sdl_ver="2.24.0"
test -z "$luajit_ver" && luajit_ver="2.1.0-beta3"

test -d external || mkdir external

if [ ! -f external/.stamp_SDL2 ]; then
	test -f SDL2-${sdl_ver}.tar.gz || wget https://github.com/libsdl-org/SDL/releases/download/release-${sdl_ver}/SDL2-${sdl_ver}.tar.gz
	rm -rf SDL2-${sdl_ver}

	tar xf SDL2-${sdl_ver}.tar.gz
	cd SDL2-${sdl_ver}
	./configure --prefix=`pwd`/../external/ --disable-shared --enable-static --enable-joystick --disable-sensor --disable-power --disable-haptic --disable-filesystem --disable-file --disable-video-vulkan --enable-video-opengl --disable-video-opengles2 --disable-video-vivante --disable-video-cocoa --disable-video-metal --disable-render-metal --disable-video-kmsdrm --disable-video-opengles --disable-video-opengles1 --disable-video-opengles2 --disable-video-vulkan --disable-render-d3d --disable-sdl2-config --enable-alsa
	make && make install
	cd ..

	rm -rf SDL2-${sdl_ver}

	tar xf SDL2-${sdl_ver}.tar.gz
	cd SDL2-${sdl_ver}
	./configure CFLAGS="-funwind-tables" --prefix=`pwd`/../external/windows/ --host=i686-w64-mingw32 --enable-shared --enable-static --enable-joystick --disable-sensor --disable-power --disable-haptic --disable-filesystem --disable-file --disable-video-vulkan --enable-video-opengl --disable-video-opengles2 --disable-video-vivante --disable-video-cocoa --disable-video-metal --disable-render-metal --disable-video-kmsdrm --disable-video-opengles --disable-video-opengles1 --disable-video-opengles2 --disable-video-vulkan --disable-render-d3d
	make && make install
	cd ..
	touch external/.stamp_SDL2
fi

if [ ! -f external/.stamp_luajit ]; then
	test -f LuaJIT-${luajit_ver}.tar.gz || wget https://luajit.org/download/LuaJIT-${luajit_ver}.tar.gz
	rm -rf LuaJIT-${luajit_ver}

	tar xf LuaJIT-${luajit_ver}.tar.gz
	cd LuaJIT-${luajit_ver}
	make DEFAULT_CC="gcc" BUILDMODE=static V=1
	cp src/libluajit.a ../external/lib/
	for f in lua.h luaconf.h lualib.h lauxlib.h; do
		cp src/$f ../external/include/
	done
	make clean
	make CROSS=i686-w64-mingw32- TARGET_CFLAGS=-funwind-tables HOST_CC="gcc -m32" TARGET_SYS=Windows BUILDMODE=static
	for f in lua.h luaconf.h lualib.h lauxlib.h; do
		cp src/$f ../external/windows/include/
	done
	cp src/libluajit.a ../external/windows/lib/
	cd ..
	touch external/.stamp_luajit
fi

## Linux version

gcc -DVERSION=\"`date +%y%m%d`\" -Wall -O3 -Wl,-Bstatic \
-Iexternal/include \
-Iexternal/include/SDL2 \
src/*.c \
-Lexternal/lib/ \
-D_REENTRANT -Dunix -Wl,--no-undefined \
-lSDL2 \
-lluajit \
-Wl,-Bdynamic \
-lm -ldl -lpthread -lc \
-o rein
strip rein

## Windows version

CFLAGS="-Isrc/instead -Iexternal/windows/include -Iexternal/windows/include/SDL2"
LDFLAGS="-Lexternal/windows/lib -lSDL2.dll -lSDL2main -lm -lluajit -lws2_32 -lwsock32"

i686-w64-mingw32-windres -i contrib/resources.rc -o resources.o || exit 1

i686-w64-mingw32-gcc -funwind-tables -DVERSION=\"`date +%y%m%d`\" -Wall -static -O3 $CFLAGS src/*.c resources.o $LDFLAGS -mwindows -o rein.exe || exit 1
i686-w64-mingw32-strip rein.exe
rm -f *.o

## make release

rm -rf release
mkdir release

cp rein release/rein.x86-64.linux
cp -r rein.exe demo/ data/ doc/ COPYING ChangeLog external/windows/bin/*.dll release/
i686-w64-mingw32-strip release/SDL2.dll
