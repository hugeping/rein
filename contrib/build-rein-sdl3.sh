# Build rein with SDL3 for Linux and Windows (mingw-w64), both static.
# Usage: contrib/build-rein-sdl3.sh [linux|windows|all]
# Artifacts are placed into dist/<target>/.
# Run from the repository root.
# Requires: cmake, gcc, pkg-config, wget, git + mingw-w64 for the windows target.

set -e

target="${1:-all}"
sdl_ver="${sdl_ver:-3.4.16}"
luajit_ver="${luajit_ver:-2.1}"
VERSION="${VERSION:-`date +%y%m%d`}"

mkdir -p external dist

fetch_sdl3_src()
{
	test -f external/SDL3-$sdl_ver.tar.gz || wget -q -O external/SDL3-$sdl_ver.tar.gz \
		https://github.com/libsdl-org/SDL/releases/download/release-$sdl_ver/SDL3-$sdl_ver.tar.gz
	if [ ! -d external/sdl3-src ]; then
		mkdir -p external/sdl3-src
		tar xf external/SDL3-$sdl_ver.tar.gz -C external/sdl3-src --strip-components=1
	fi
}

build_linux()
{
	fetch_sdl3_src
	if [ ! -f external/.stamp-sdl3 ]; then
		rm -rf external/sdl3-build external/sdl3
		cmake -S external/sdl3-src -B external/sdl3-build \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX="$PWD/external/sdl3" \
			-DSDL_SHARED=OFF -DSDL_STATIC=ON \
			-DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_INSTALL_TESTS=OFF \
			-DSDL_KMSDRM=OFF -DSDL_VULKAN=OFF \
			-DSDL_OPENGLES=OFF \
			-DSDL_PULSEAUDIO=OFF -DSDL_PIPEWIRE=OFF -DSDL_JACK=OFF
		cmake --build external/sdl3-build -j`nproc`
		cmake --install external/sdl3-build
		touch external/.stamp-sdl3
	fi
	if [ ! -f external/.stamp-luajit ]; then
		rm -rf external/luajit
		git clone --depth 1 -b v$luajit_ver https://github.com/LuaJIT/LuaJIT.git external/luajit
		make -C external/luajit BUILDMODE=static DEFAULT_CC=gcc
		touch external/.stamp-luajit
	fi
	mkdir -p dist/linux
	gcc -DVERSION=\"$VERSION\" -Wall -O3 \
		-Iexternal/sdl3/include -Iexternal/luajit/src \
		src/*.c src/tls/*.c src/sdl3/platform.c \
		-Lexternal/sdl3/lib -lSDL3 \
		-Lexternal/luajit/src -lluajit \
		-lm -ldl -lpthread \
		-o dist/linux/rein-x86-64-linux
	strip dist/linux/rein-x86-64-linux
	cp -r data demo doc COPYING ChangeLog dist/linux/
}

build_windows()
{
	fetch_sdl3_src
	if [ ! -f external/.stamp-sdl3-win ]; then
		rm -rf external/sdl3-build-win external/sdl3-win
		cmake -S external/sdl3-src -B external/sdl3-build-win \
			-DCMAKE_TOOLCHAIN_FILE="$PWD/external/sdl3-src/build-scripts/cmake-toolchain-mingw64-x86_64.cmake" \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX="$PWD/external/sdl3-win" \
			-DSDL_SHARED=OFF -DSDL_STATIC=ON \
			-DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_INSTALL_TESTS=OFF
		cmake --build external/sdl3-build-win -j`nproc`
		cmake --install external/sdl3-build-win
		touch external/.stamp-sdl3-win
	fi
	if [ ! -f external/.stamp-luajit-win ]; then
		rm -rf external/luajit-win
		git clone --depth 1 -b v$luajit_ver https://github.com/LuaJIT/LuaJIT.git external/luajit-win
		make -C external/luajit-win CROSS=x86_64-w64-mingw32- TARGET_SYS=Windows \
			BUILDMODE=static HOST_CC="gcc"
		touch external/.stamp-luajit-win
	fi
	SDL3_LIBS=`PKG_CONFIG_LIBDIR="$PWD/external/sdl3-win/lib/pkgconfig" pkg-config --static --libs sdl3`
	mkdir -p dist/windows
	x86_64-w64-mingw32-gcc -funwind-tables -DVERSION=\"$VERSION\" -Wall -O3 \
		-static -mwindows \
		-Iexternal/sdl3-win/include -Iexternal/luajit-win/src \
		src/*.c src/tls/*.c src/sdl3/platform.c \
		$SDL3_LIBS \
		-Lexternal/luajit-win/src -lluajit -lws2_32 -lwsock32 \
		-o dist/windows/rein.exe
	x86_64-w64-mingw32-strip dist/windows/rein.exe
	cp -r data demo doc COPYING ChangeLog dist/windows/
}

case "$target" in
linux)
	build_linux
	;;
windows)
	build_windows
	;;
all)
	build_linux
	build_windows
	;;
*)
	echo "usage: $0 [linux|windows|all]" >&2
	exit 1
	;;
esac
