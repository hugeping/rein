# Build rein for the browser with the emscripten SDL3 port.
# Lua sources are downloaded into src/lua on first run.
# The emcc environment (emsdk) must be active.
# Usage: contrib/build-rein-em.sh (run from the repository root)

set -e

lua_ver="${lua_ver:-5.4.6}"

if [ ! -d src/lua ]; then
	mkdir -p external
	test -f external/lua-$lua_ver.tar.gz || wget -q -O external/lua-$lua_ver.tar.gz \
		https://www.lua.org/ftp/lua-$lua_ver.tar.gz
	tar xf external/lua-$lua_ver.tar.gz -C external
	rm -rf src/lua
	mkdir -p src/lua
	cp external/lua-$lua_ver/src/* src/lua/
	rm -f src/lua/lua.c src/lua/luac.c
fi

VERSION=`date +%y%m%d`
mkdir -p dist/emscripten

emcc -O2 -o dist/emscripten/rein.html \
	src/*.c src/tls/*.c src/sdl3/platform.c src/lua/*.c \
	-Isrc/lua \
	-sUSE_SDL=3 -DDATADIR=\"/data\" -DVERSION=\"$VERSION\" \
	-lidbfs.js -sWASM=1 -sALLOW_MEMORY_GROWTH=1 \
	--preload-file data/ \
	--post-js=contrib/post.js -sINVOKE_RUN=0 \
	-sEXPORTED_RUNTIME_METHODS=callMain

cp contrib/rein.html dist/emscripten/
