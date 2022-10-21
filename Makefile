all:	dein

CFLAGS=$(shell pkg-config --cflags sdl2) $(shell pkg-config --cflags luajit) -Dunix -Wall -O3
LDFLAGS=$(shell pkg-config --libs sdl2) $(shell pkg-config --libs luajit) -lm

# uncomment for system-wide install
# PREFIX=/usr/local

ifneq ($(PREFIX),)
DATADIR=-DDATADIR=\"$(PREFIX)/share/dein\"
install: dein
	install -d -m 0755 $(DESTDIR)$(PREFIX)/bin
	install -d -m 0755 $(DESTDIR)$(PREFIX)/share/dein
	install -m 0755 dein $(DESTDIR)$(PREFIX)/bin
	cp -r data/* $(DESTDIR)$(PREFIX)/share/dein
	install -d -m 0755 $(DESTDIR)$(PREFIX)/share/pixmaps/

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/dein
	rm -rf $(DESTDIR)$(PREFIX)/share/dein
endif

CFILES= \
	src/platform.c \
	src/stb_image.c \
	src/lua-compat.c \
	src/stb_image_resize.c \
	src/bit.c \
	src/main.c \
	src/gfx.c \
	src/system.c \
	src/gfx_font.c \
	src/stb_truetype.c

OFILES  := $(patsubst %.c, %.o, $(CFILES))

$(OFILES): %.o : %.c
	$(CC) -c $(<) $(I) $(CFLAGS) $(DATADIR) -o $(@)

dein:  $(OFILES)
	$(CC) $(CFLAGS) $(^) $(LDFLAGS) -o $(@)

clean:
	$(RM) -f src/lua/*.o src/*.o dein
