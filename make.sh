CFLAGS="`pkg-config --cflags sdl2` `pkg-config --cflags luajit`"
LDFLAGS="`pkg-config --libs sdl2` `pkg-config --libs luajit` -lm"
gcc -Wall -O3 src/*.c $CFLAGS $LDFLAGS -o dein
rm -f *.o
