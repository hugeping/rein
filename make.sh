CFLAGS="`pkg-config --cflags sdl3` `pkg-config --cflags lua5.4`"
LDFLAGS="`pkg-config --libs sdl3` `pkg-config --libs lua5.4` -lm"
gcc -fsanitize=address,undefined -ggdb -O0 -Wall -O3 src/*.c src/sdl3/platform.c $CFLAGS $LDFLAGS -o rein -DVERSION=\"`date +%y%m%d`\"
rm -f *.o
