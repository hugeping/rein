#define _PLAN9_SOURCE
#include <u.h>
#include <fcntl.h>
#include <unistd.h>
//#include <libc.h>
#include <draw.h>
#include <event.h>
#include <keyboard.h>
#include <time.h>
#include <sys/time.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "../platform.h"
static unsigned char *pixels = nil;
static Image *windbuf = nil;

void
Log(const char *msg)
{
	printf("%s\n", msg);
}

void
TextInput(void)
{
}

static int resized = 0;

void eresized(int new)
{
	int w, h;
	if (new && getwindow(display, Refnone) < 0) {
		fprintf(stderr, "cannot reattach to window\n");
		exit(1);
	}
	resized ++;
}

void
WindowTitle(const char *title)
{
	int f;

	f = open("/dev/label", 1|16|32);
	if (f < 0)
		f = open("/mnt/term/dev/label", 1|16|32);
	if (f < 0)
		return;
	write(f, title, strlen(title));
	close(f);
}

int
PlatformInit(void)
{
	if(initdraw(nil, nil, "core") < 0)
		return -1;
	einit(Emouse|Ekeyboard);
	eresized(0);
	WindowResize(Dx(screen->r), Dy(screen->r));
	return 0;
}

void
PlatformDone(void)
{
}

void Delay(float n)
{
	struct timespec tim;
	tim.tv_sec = floor(n);
	tim.tv_nsec = (n - (time_t)n) * 1000000000;
	nanosleep(&tim , NULL);
}

static int exposed = 0;

int WaitEvent(float n)
{
	ulong keys = (Emouse|Ekeyboard);
	if (!exposed | resized)
		return 1;
	while (!ecanread(keys)) {
		struct timespec tim;
		tim.tv_sec = 0;
		tim.tv_nsec = 0.01 * 1000000000;
		if (nanosleep(&tim , NULL) < 0)
			break;
		n -= 0.01;
		if (n <= 0.0f)
			break;
	}
	return ecanread(keys);
}

int WindowCreate(void)
{
	return 0;
}

static int win_w;
static int win_h;

void WindowResize(int w, int h)
{
	pixels = realloc(pixels, w * h * 4);
	if (windbuf)
		freeimage(windbuf);
	windbuf = allocimage(display, Rect(0, 0, w, h), XBGR32, 0, DBlack);
	win_w = w;
	win_h = h;
}

void WindowUpdate(int x, int y, int w, int h)
{
	Rectangle r = Rect(0, 0, win_w, win_h);
	if (w > 0 && h > 0) { /* update region */
		Point p;
		unsigned char *buf, *src, *dst;
		if (x < 0) {
			w += x;
			x = 0;
		}
		if (y < 0) {
			h += y;
			y = 0;
		}
		if (y + h > win_h)
			h = win_h - y;
		if (x + w > win_w)
			w = win_w - x;
		if (w <= 0 || h <= 0)
			return;
		buf = malloc(w * h * 4);
		if (!buf)
			return;
		src = pixels + x * 4 + y * win_w * 4;
		dst = buf;
		for (int yy = 0; yy < h; yy ++) {
			memcpy(dst, src, w * 4);
			src += win_w * 4;
			dst += w * 4;
		}
		loadimage(windbuf, Rect(0, 0, w, h), (unsigned char *)buf, w * h * 4);
		p.x = -x; p.y = -y;
		replclipr(screen, 0, rectaddpt(Rect(0, 0, w, h),
			Pt(screen->r.min.x + x, screen->r.min.y + y)));
		draw(screen, screen->r, windbuf, nil, p);
		free(buf);
	} else {
		loadimage(windbuf, r, pixels, win_w * win_h * 4);
		replclipr(screen, 0, screen->r);
		draw(screen, screen->r, windbuf, nil, ZP);
	}
	flushimage(display, 1);
}

unsigned char *WindowPixels(int *w, int *h)
{
	*w = win_w;
	*h = win_h;
	return pixels;
}

void WindowMode(int n)
{
}

double Time(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return (double)tv.tv_sec + (double)(tv.tv_usec) / 1000000;
}

float GetScale(void)
{
	return 1.0f;
}

const char *GetPlatform(void)
{
	return "Plan9";
}

const char *GetExePath(const char *progname)
{
	static char exepath[4096];
	static char cwd[4096];
	if (progname[0] == '/')
		return progname;
	snprintf(exepath, sizeof(exepath), "%s/%s", getcwd(cwd, sizeof(cwd)), progname);
	return exepath;
}

void Icon(unsigned char *ptr, int w, int h)
{
	return;
}

static int mb = 0;
extern int sys_poll(lua_State *L)
{
	char sym[UTFmax+1];
	ulong keys = (Emouse|Ekeyboard);
	Event ev;
	Rune r;
	int n;
	int e;
	if (resized > 0) {
		resized = 0;
		WindowResize(Dx(screen->r), Dy(screen->r));
		lua_pushstring(L, "exposed");
		return 1;
	}
	if (!exposed) {
		exposed = 1;
		lua_pushstring(L, "exposed");
		return 1;
	}
again:
	while (ecanread(keys) == 1) {
		e = eread(keys, &ev);
		switch(e) {
		case Ekeyboard:
			r = ev.kbdc;
			switch (r) {
			case 0x10:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "==");
				return 2;
			case 0x1d:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "++");
				return 2;
			case 0x0d:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "--");
				return 2;
			case '\n':
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "return");
				return 2;
			case Ketb:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "Ketb");
				return 2;
			case Knack:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "Knack");
				return 2;
			case Ksoh:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "home");
				return 2;
			case Kenq:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "end");
				return 2;
			case Kesc:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "escape");
				return 2;
			case Kpgup:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "pageup");
				return 2;
			case Kpgdown:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "pagedown");
				return 2;
			case Kup:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "up");
				return 2;
			case Kdown:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "down");
				return 2;
			case Kleft:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "left");
				return 2;
			case Kright:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "right");
				return 2;
			case Kbs:
				lua_pushstring(L, "keydown");
				lua_pushstring(L, "backspace");
				return 2;
			}
			n = runetochar(sym, &r);
			sym[n] = 0;
			if (n > 0) {
				lua_pushstring(L, "text");
				lua_pushstring(L, sym);
				return 2;
			}
			break;
		case Emouse:
			if ((mb&1) != (ev.mouse.buttons &1)) {
				if (ev.mouse.buttons & 1)
					lua_pushstring(L, "mousedown");
				else
					lua_pushstring(L, "mouseup");
				lua_pushstring(L, "left");
				lua_pushnumber(L, ev.mouse.xy.x - screen->r.min.x);
				lua_pushnumber(L, ev.mouse.xy.y - screen->r.min.y);
				mb = ev.mouse.buttons;
				return 4;
			}
			if (ev.mouse.buttons & 0x10) {
				lua_pushstring(L, "mousewheel");
				lua_pushnumber(L, -1);
				return 2;
			} else if (ev.mouse.buttons & 0x08) {
				lua_pushstring(L, "mousewheel");
				lua_pushnumber(L, 1);
				return 2;
			}
			lua_pushstring(L, "mousemotion");
			lua_pushnumber(L, ev.mouse.xy.x - screen->r.min.x);
			lua_pushnumber(L, ev.mouse.xy.y - screen->r.min.y);
			return 3;
		default:
			goto again;
		}
	}
	return 0;
}

char *dirname(char *path)
{
	char *p;
	if (path == nil || *path == '\0')
		return ".";
	p = path + strlen(path) - 1;
	while (*p == '/') {
		if (p == path)
			return path;
		*p-- = '\0';
	}
	while (p >= path && *p != '/')
		p--;
	return p < path ? "." : p == path ? "/" : (*p = '\0', path);
}

void Speak(const char *txt)
{
}

int isSpeak(void)
{
	return 0;
}
