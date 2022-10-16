CFLAGS="`pkg-config --cflags sdl2` -Isrc/lua -Dunix -DSDL_DISABLE_IMMINTRIN_H -DSTBI_NO_SIMD"
LDFLAGS="`pkg-config --libs sdl2` -lm"
tcc -o dein src/*.c src/lua/*.c $CFLAGS $LDFLAGS
rm -f *.o
