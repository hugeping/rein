all:	rein

VERSION := $(shell date +%y%m%d)
CFLAGS=$(shell pkg-config --cflags sdl2) $(shell pkg-config --cflags luajit) -Wall -O3 -DVERSION=\"${VERSION}\"
LDFLAGS=$(shell pkg-config --libs sdl2) $(shell pkg-config --libs luajit) -lm

# uncomment for system-wide install
# PREFIX=/usr/local

ifneq ($(PREFIX),)
DATADIR=-DDATADIR=\"$(PREFIX)/share/rein\"
install: rein
	install -d -m 0755 $(DESTDIR)$(PREFIX)/bin
	install -d -m 0755 $(DESTDIR)$(PREFIX)/share/rein
	install -m 0755 rein $(DESTDIR)$(PREFIX)/bin
	cp -r data/* $(DESTDIR)$(PREFIX)/share/rein
	install -d -m 0755 $(DESTDIR)$(PREFIX)/share/pixmaps/

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/rein
	rm -rf $(DESTDIR)$(PREFIX)/share/rein
endif

CFILES= \
	src/platform.c \
	src/stb_image.c \
	src/lua-compat.c \
	src/stb_image_resize.c \
	src/bit.c \
	src/thread.c \
	src/main.c \
	src/gfx.c \
	src/system.c \
	src/gfx_font.c \
	src/stb_truetype.c \
	src/tinymt32.c

OFILES  := $(patsubst %.c, %.o, $(CFILES))

$(OFILES): %.o : %.c
	$(CC) -c $(<) $(I) $(CFLAGS) $(DATADIR) -o $(@)

rein:  $(OFILES)
	$(CC) $(CFLAGS) $(^) $(LDFLAGS) -o $(@)

clean:
	$(RM) -f src/lua/*.o src/*.o rein
