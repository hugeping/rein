. /home/peter/Devel/emsdk-portable/emsdk/emsdk_env.sh
emcc -O2 -o rein.html src/*.c src/lua/*.c -Isrc/lua -s USE_SDL=2 -DDATADIR=\"/data\" \
-lidbfs.js -s WASM=1 -s SAFE_HEAP=0  -s ALLOW_MEMORY_GROWTH=1 \
--preload-file data/ \
--post-js=contrib/post.js -s INVOKE_RUN=0
