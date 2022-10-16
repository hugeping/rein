CFLAGS="`sdl2-config --cflags` -Isrc/lua -Dunix"
LDFLAGS="`sdl2-config --libs` -lm"
gcc -Wall -O3 src/*.c src/lua/*.c $CFLAGS $LDFLAGS -o dein
rm -f *.o
