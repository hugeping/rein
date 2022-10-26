CFLAGS="`pkg-config --cflags sdl2` `pkg-config --cflags luajit`"
LDFLAGS="`pkg-config --libs sdl2` `pkg-config --libs luajit` -lm"
gcc -Wall -O3 src/*.c $CFLAGS $LDFLAGS -o dein -DVERSION=\"`date +%y%m%d`\"
rm -f *.o
