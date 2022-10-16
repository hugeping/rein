CFLAGS="-Isrc/instead -Iwindows/ -Iwindows/SDL2"
LDFLAGS="windows/libluajit.a -Lwindows/SDL2 -lSDL2 -lSDL2main -lm"

i686-w64-mingw32-windres -i windows/resources.rc -o resources.o || exit 1
i686-w64-mingw32-gcc -Wall -O3 src/*.c resources.o $CFLAGS $LDFLAGS -mwindows -o dein.exe || exit 1
i686-w64-mingw32-strip dein.exe

rm -f *.o
