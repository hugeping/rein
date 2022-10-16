</$objtype/mkfile
CC=pcc
CFLAGS=-D_POSIX_SOURCE -Isrc/lua -DPLAN9

all: dein
	

CFILES= \
	src/plan9/platform.c \
	src/stb_image.c \
	src/lua-compat.c \
	src/stb_image_resize.c \
	src/stb_truetype.c \
	src/main.c \
	src/gfx.c \
	src/gfx_font.c \
	src/system.c \
	src/lua/lapi.c \
	src/lua/lauxlib.c \
	src/lua/lbaselib.c \
	src/lua/lcode.c \
	src/lua/lcorolib.c \
	src/lua/lctype.c \
	src/lua/ldblib.c \
	src/lua/ldebug.c \
	src/lua/ldo.c \
	src/lua/ldump.c \
	src/lua/lfunc.c \
	src/lua/lgc.c \
	src/lua/linit.c \
	src/lua/liolib.c \
	src/lua/llex.c \
	src/lua/lmathlib.c \
	src/lua/lmem.c \
	src/lua/loadlib.c \
	src/lua/lobject.c \
	src/lua/lopcodes.c \
	src/lua/loslib.c \
	src/lua/lparser.c \
	src/lua/lstate.c \
	src/lua/lstring.c \
	src/lua/lstrlib.c \
	src/lua/ltable.c \
	src/lua/ltablib.c \
	src/lua/ltm.c \
	src/lua/lundump.c \
	src/lua/lutf8lib.c \
	src/lua/lvm.c \
	src/lua/lzio.c \

OFILES=${CFILES:%.c=%.$O}

%.$O: %.c
	$CC $CFLAGS -c -o $target $stem.c

dein: $OFILES
	$LD -o $target $OFILES

clean nuke:V:
	rm -f src/plan9/*.[$OS] src/lua/*.[$OS] src/*.[$OS] [$OS].out dein
