#include <SDL.h>
#include "external.h"
#include "platform.h"

#ifdef __ANDROID__
#include <jni.h>
#include <android/log.h>
#define LOG(s) do { __android_log_print(ANDROID_LOG_VERBOSE, "rein", "%s", s); } while(0)
#else
#define LOG(s) do { printf("%s\n", (s)); } while(0)
#endif
static int opt_nosound = 0;
static int opt_nojoystick = 0;
static int opt_xclip = 0;

static int destroyed = 0;
static void
tolow(char *p)
{
	while (*p) {
		if (*p >=  'A' && *p <= 'Z')
			*p |= 0x20;
		p ++;
	}
}

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *texture = NULL;
static SDL_Texture *expose_texture = NULL;
static SDL_RendererInfo renderer_info;

static float scalew, scaleh;

void
Log(const char *msg)
{
	LOG(msg);
}

void
TextInput(void)
{
	SDL_StartTextInput();
}

double
Time(void)
{
	return SDL_GetPerformanceCounter() / (double) SDL_GetPerformanceFrequency();
}

void
WindowMode(int n)
{
	SDL_SetWindowFullscreen(window,
		n == WIN_FULLSCREEN ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
	if (n == WIN_NORMAL)
		SDL_RestoreWindow(window);
	else if (n == WIN_MAXIMIZED)
		SDL_MaximizeWindow(window);
}

void
WindowTitle(const char *title)
{
	SDL_SetWindowTitle(window, title);
}

#if 1
/* SDL2 realization after 2.0.16 may sleep. BUG? */
int
SDL_WaitEventTo(int timeout)
{
	Uint32 expiration = 0;

	if (timeout > 0)
		expiration = SDL_GetTicks() + timeout;

	for (;;) {
		SDL_PumpEvents();
		switch (SDL_PeepEvents(NULL, 1, SDL_GETEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT)) {
		case -1:
			return 0;
		case 0:
			if (timeout == 0)
				return 0;
			if (timeout > 0 && SDL_TICKS_PASSED(SDL_GetTicks(), expiration))
				return 0;
			if (timeout >= 100) /* 1/10 */
				SDL_Delay(10);
			else if (timeout >= 10) /* 1/100 */
				SDL_Delay(2);
			else
				SDL_Delay(1);
			break;
		default:
			/* Has events */
			return 1;
		}
	}
}
#endif

void
WakeEvent(void)
{
	SDL_Event event;
	memset(&event, 0, sizeof(event));
	event.type = SDL_USEREVENT;
	SDL_PushEvent(&event);
	return;
}

int
WaitEvent(float n)
{
/* standard function may sleep longer than 20ms (in Windows) */
//	if (n >= 0.05f)
//		return SDL_WaitEventTimeout(NULL, (int)(n * 1000));
//	else
		return SDL_WaitEventTo((int)(n * 1000));
}

void
Delay(float n)
{
	SDL_Delay(n * 1000);
}

static char*
key_name(int sym)
{
	static char dst[16];
	strcpy(dst, SDL_GetScancodeName(sym));
	tolow(dst);
	return dst;
}

static char*
gamepad_key(int code)
{
	static char dst[16];
	const char *key;
	switch(code) {
	case SDL_CONTROLLER_BUTTON_DPAD_UP:
		key = "up";
		break;
	case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
		key = "down";
		break;
	case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
		key = "left";
		break;
	case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
		key = "right";
		break;
	case SDL_CONTROLLER_BUTTON_A:
		key = "z";
		break;
	case SDL_CONTROLLER_BUTTON_B:
		key = "x";
		break;
	case SDL_CONTROLLER_BUTTON_X:
		key = "c";
		break;
	case SDL_CONTROLLER_BUTTON_Y:
		key = "space";
		break;
	case SDL_CONTROLLER_BUTTON_START:
		key = "escape";
		break;
	case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:
		key = "left shift";
		break;
	case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
		key = "right shift";
		break;
	default:
		key = "unknown";
		break;
	}
	strncpy(dst, key, sizeof(dst));
	dst[sizeof(dst)-1] = 0;
	return dst;
}

static char*
button_name(int button)
{
	static char nam[16];
	switch (button) {
	case 1:
		strcpy(nam, "left");
		break;
	case 2:
		strcpy(nam, "middle");
		break;
	case 3:
		strcpy(nam, "right");
		break;
	default:
		snprintf(nam, sizeof(nam), "btn%d", button);
		break;
	}
	nam[sizeof(nam)-1] = 0;
	return nam;
}
float
GetScale(void)
{
#ifdef __EMSCRIPTEN__
	double r = EM_ASM_DOUBLE({
		return window.devicePixelRatio;
	});
	return (float)r;
#else
	float dpi;
	int disp = window?SDL_GetWindowDisplayIndex(window):0;
	if (SDL_GetDisplayDPI(disp, NULL, &dpi, NULL))
		return 1.0f;
	return dpi / 96.0f;
#endif
}

#ifdef _WIN32
static HINSTANCE user32_lib;
#endif

static SDL_AudioSpec audiospec;
static SDL_AudioDeviceID audiodev;

struct {
	unsigned char *data;
	unsigned int head;
	unsigned int tail;
	unsigned int size;
	unsigned int free;
} audiobuff;

unsigned int
AudioWrite(void *data, unsigned int size)
{
	unsigned int pos, rc, towrite;
	unsigned char *buf = data;
	if (!audiodev)
		return size;
	SDL_LockAudioDevice(audiodev);
	if (!data) { /* get avail space */
		rc = audiobuff.free;
		SDL_UnlockAudioDevice(audiodev);
		return rc;
	}
	towrite = (size >= audiobuff.free)?audiobuff.free:size;
	pos = audiobuff.tail;
	audiobuff.free -= towrite;
	rc = towrite;
	while (towrite--)
		audiobuff.data[pos++ % audiobuff.size] = *(buf ++);
	audiobuff.tail = pos % audiobuff.size;
	SDL_UnlockAudioDevice(audiodev);
	return rc;
}

static unsigned int
audio_read(uint8_t *stream, int len)
{
	unsigned int used, toread, pos, rc;
	SDL_LockAudioDevice(audiodev);
	used = audiobuff.size - audiobuff.free;
	toread = (len>=used)?used:len;
	if (toread < len)
		memset(stream + toread, 0, (len - toread));
	audiobuff.free += toread;
	pos = audiobuff.head;
	rc = toread;
	while (toread--)
		*(stream++) = audiobuff.data[pos ++ % audiobuff.size];
	audiobuff.head = pos % audiobuff.size;
	SDL_UnlockAudioDevice(audiodev);
	return rc;
}

static void
audio_cb(void *userdata, uint8_t *stream, int len)
{
	audio_read(stream, len);
}

void
MouseHide(int off)
{
	SDL_ShowCursor(!off?SDL_ENABLE:SDL_DISABLE);
}

static SDL_GameController *gamepad = NULL;

static void
gamepad_init(void)
{
	int i;

	if (opt_nojoystick)
		return;

	if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) < 0) {
		fprintf(stderr, "Couldn't initialize GameController subsystem: %s\n", SDL_GetError());
		return;
	}
	for (i = 0; i < SDL_NumJoysticks(); ++i) {
		if (SDL_IsGameController(i)) {
			gamepad = SDL_GameControllerOpen(i);
			if (gamepad) {
				fprintf(stdout, "Found gamepad: %s\n",
					SDL_GameControllerName(gamepad));
				break;
			} else {
				fprintf(stderr, "Could not open gamepad %i: %s\n",
					i, SDL_GetError());
			}
		}
	}
}

static void
gamepad_done(void)
{
	if(gamepad)
		SDL_GameControllerClose(gamepad);
	if(SDL_WasInit(SDL_INIT_GAMECONTROLLER))
		SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
}

static void
sound_init(void)
{
	SDL_AudioSpec spec;
	if (opt_nosound)
		return;
	if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
		fprintf(stderr, "Couldn't initialize Audio subsystem: %s\n", SDL_GetError());
		return;
	}
	spec.freq = 44100;
	spec.format = AUDIO_S16;
	spec.channels = 2;
	spec.samples = 1024 * spec.channels;
	spec.callback = audio_cb;
	spec.userdata = NULL;
	audiodev = SDL_OpenAudioDevice(NULL, 0, &spec, &audiospec, 0);
	if (audiodev) {
		printf("Audio: %dHz channels: %d size: %d\n", audiospec.freq,
			audiospec.channels,
			audiospec.samples);
		audiobuff.size = audiospec.samples * spec.channels * 2 * 2;
		audiobuff.free = audiobuff.size;
		audiobuff.data = malloc(audiobuff.size);
		audiobuff.head = 0;
		audiobuff.tail = 0;
	} else {
		fprintf(stderr, "No audio: %s\n", SDL_GetError());
	}
	SDL_PauseAudioDevice(audiodev, 0);
}

static void
sound_done(void)
{
	SDL_PauseAudioDevice(audiodev, 1);
	if (audiodev)
		SDL_CloseAudioDevice(audiodev);
	if (SDL_WasInit(SDL_INIT_AUDIO))
		SDL_QuitSubSystem(SDL_INIT_AUDIO);
}

int
PlatformInit(int argc, const char **argv)
{
#ifdef _WIN32
	WSADATA wsaData;

	int (*SetProcessDPIAware)();
	user32_lib = LoadLibrary("user32.dll");
	SetProcessDPIAware = (void*) GetProcAddress(user32_lib, "SetProcessDPIAware");
	if (SetProcessDPIAware)
		SetProcessDPIAware();

	if (WSAStartup(MAKEWORD(1,1), &wsaData) != 0) {
		fprintf(stderr, "Couldn't initialize Winsock 1.1\n");
	}
#endif
#if SDL_VERSION_ATLEAST(2, 0, 8)
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
#endif
	if (argv) {
		int i;
		for (i = 0; i < argc; i ++) {
			if (!strcmp(argv[i], "-platform-nosound"))
				opt_nosound = 1;
			else if (!strcmp(argv[i], "-platform-nojoystick"))
				opt_nojoystick = 1;
			else if (!strcmp(argv[i], "-platform-xclip"))
				opt_xclip = 1;
			else if (!strcmp(argv[i], "-platform-xclip-only"))
				opt_xclip = 2;
		}
	}

	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS))
		return -1;
	sound_init();
	gamepad_init();
//	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
	return 0;
}

static SDL_Surface *winbuff = NULL;

void
PlatformDone(void)
{
	gamepad_done();
	sound_done();
#ifdef _WIN32
	if (user32_lib)
		FreeLibrary(user32_lib);
	WSACleanup();
#endif
	if (winbuff)
		SDL_FreeSurface(winbuff);
	if (texture)
		SDL_DestroyTexture(texture);
	if (expose_texture)
		SDL_DestroyTexture(expose_texture);
	if (renderer)
		SDL_DestroyRenderer(renderer);
	SDL_DestroyWindow(window);
	SDL_Quit();
#ifdef __ANDROID__
	_exit(0);
#endif
}

const char *
GetPlatform(void)
{
	return SDL_GetPlatform();
}

const char *
GetLanguage(void)
{
	static char b[16] = {0};
#if SDL_VERSION_ATLEAST(2,0,14)
	SDL_Locale *l = SDL_GetPreferredLocales();
	snprintf(b, 16, "%s", l && l->language ? l->language : "");
	SDL_free(l);
#endif
	return b;
}


int
WindowCreate(void)
{
	SDL_DisplayMode mode;
	SDL_GetCurrentDisplayMode(0, &mode);
	if (SDL_CreateWindowAndRenderer(mode.w * 0.5, mode.h * 0.8,
#ifdef __EMSCRIPTEN__
		SDL_WINDOW_RESIZABLE, &window, &renderer))
#else
		SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_HIDDEN, &window, &renderer))
#endif
		return -1;
	SDL_GetRendererInfo(renderer, &renderer_info);
	fprintf(stdout, "Video: %s%s\n", renderer_info.name,
		(renderer_info.flags & SDL_RENDERER_ACCELERATED)?" (accelerated)":"");
	SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
	SDL_ShowWindow(window);
	return 0;
}

static void
unix_path(char *path)
{
	char *p = path;
	if (!path)
		return;
	while (*p) { /* bad Windows!!! */
		if (*p == '\\')
			*p = '/';
		p ++;
	}
	return;
}

const char *
GetExePath(const char *progname)
{
	static char path[4096];
#if _WIN32
	int len = GetModuleFileName(NULL, path, sizeof(path) - 1);
	path[len] = 0;
#elif __APPLE__
	unsigned size = sizeof(path);
	_NSGetExecutablePath(path, &size);
#elif __linux__
	int len;
	char proc_path[256];
	snprintf(proc_path, sizeof(proc_path), "/proc/%d/exe", getpid());
	len = readlink(proc_path, path, sizeof(path) - 1);
	path[len] = 0;
#else
	strncpy(path, progname, sizeof(path));
#endif
	path[sizeof(path) - 1] = 0;
	unix_path(path);
	return path;
}

void
WindowResize(int w, int h)
{
	if (winbuff)
		SDL_FreeSurface(winbuff);
	winbuff = NULL;
	if (texture)
		SDL_DestroyTexture(texture);
	texture = NULL;
	destroyed = 1;
}

unsigned int
GetMouse(int *ox, int *oy)
{
	Uint32 mb;
	int x, y;
	mb = SDL_GetMouseState(&x, &y);
	x = scalew*x;
	y = scaleh*y;
	if (ox)
		*ox = x;
	if (oy)
		*oy = y;
	return mb;
}

void
WindowBackground(int r, int g, int b)
{
	SDL_SetRenderDrawColor(renderer, r, g, b, 255);
}

void
WindowExpose(void *pixels, int w, int h, int dx, int dy, int dw, int dh)
{
	SDL_Rect rect;
	int ww = 0, hh = 0, rc = 1;
	if (expose_texture) {
		rc = SDL_QueryTexture(expose_texture, NULL, NULL, &ww, &hh);
		if (rc || w != hh || h != hh) {
			SDL_DestroyTexture(expose_texture);
			rc = 1;
		}
	}
	if (rc) {
		expose_texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ABGR8888,
			SDL_TEXTUREACCESS_STREAMING, w, h);
		if (!expose_texture)
			return;
	}
	SDL_UpdateTexture(expose_texture, NULL, pixels, w*4);
	SDL_RenderClear(renderer);
	if (dx || dy || dw > 0 || dh > 0) {
		rect.x = dx;
		rect.y = dy;
		if (dw <= 0 || dh <= 0)
			SDL_GetRendererOutputSize(renderer, &dw, &dh);
		rect.w = dw;
		rect.h = dh;
		SDL_RenderCopy(renderer, expose_texture, NULL, &rect);
	} else
		SDL_RenderCopy(renderer, expose_texture, NULL, NULL);
//	SDL_RenderPresent(renderer);
}

void
WindowUpdate(int x, int y, int w, int h)
{
	SDL_Rect rect;
	int pitch, psize;
	unsigned char *pixels;
	if (!winbuff || !texture)
		return;
	pitch = winbuff->pitch;
	psize = winbuff->format->BytesPerPixel;
	pixels = winbuff->pixels;
//	if (renderer_info.flags & SDL_RENDERER_ACCELERATED)
//		w = -1;
	if (w > 0 && h > 0) { /* do not flip on partial updates */
		rect.x = x;
		rect.y = y;
		rect.w = w;
		rect.h = h;
		pixels += pitch * y + x * psize;
		SDL_UpdateTexture(texture, &rect, pixels, pitch);
		SDL_RenderCopy(renderer, texture, &rect, &rect);
		return;
	} else if (w < 0 || h < 0) { /* all screen */
		SDL_UpdateTexture(texture, NULL, pixels, pitch);
		SDL_RenderClear(renderer);
		SDL_RenderCopy(renderer, texture, NULL, NULL);
		if (destroyed) { /* problem with double buffering */
			SDL_RenderPresent(renderer);
			SDL_UpdateTexture(texture, NULL, pixels, pitch);
			SDL_RenderClear(renderer);
			SDL_RenderCopy(renderer, texture, NULL, NULL);
		}
	} /* else - nothing */
	SDL_RenderPresent(renderer);
	destroyed = 0;
}

void
Icon(unsigned char *ptr, int w, int h)
{
	SDL_Surface *surf;
	surf = SDL_CreateRGBSurfaceFrom(ptr, w, h,
			32, w * 4,
			0x000000ff,
			0x0000ff00,
			0x00ff0000,
			0xff000000);
	if (!surf)
		return;
	SDL_SetWindowIcon(window, surf);
	SDL_FreeSurface(surf);
	return;
}

unsigned char *
WindowPixels(int *w, int *h)
{
	int ww, wh;
	SDL_GetWindowSize(window, &ww, &wh);
	SDL_GetRendererOutputSize(renderer, w, h);
	scalew = (float)*w/ww, scaleh = (float)*h/wh;
	if (winbuff && (winbuff->w != *w || winbuff->h != *h)) {
		SDL_FreeSurface(winbuff);
		winbuff = NULL;
		if (texture)
			SDL_DestroyTexture(texture);
		texture = NULL;
		destroyed = 1;
	}
	if (!winbuff)
		winbuff = SDL_CreateRGBSurface(0, *w, *h, 32,
			0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000);
	if (!winbuff)
		return NULL;
	if (!texture)
		texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ABGR8888,
			SDL_TEXTUREACCESS_STREAMING, *w, *h);

	return (unsigned char*)winbuff->pixels;
}

#ifdef __ANDROID__
static char edit_str[1024] = {0};
#endif

int
sys_poll(lua_State *L)
{
	SDL_Event e;
#ifdef __linux__
	pid_t pid;
	while ((pid = waitpid(-1, NULL, WNOHANG)) > 0);
#endif
top:
	if (!SDL_PollEvent(&e))
		return 0;

	switch (e.type) {
	case SDL_APP_DIDENTERBACKGROUND:
		lua_pushstring(L, "save");
		return 1;
	case SDL_QUIT:
		lua_pushstring(L, "quit");
		return 1;
	case SDL_APP_DIDENTERFOREGROUND:
		lua_pushstring(L, "exposed");
		destroyed = 1;
		return 1;
	case SDL_FINGERMOTION:
	case SDL_FINGERDOWN:
	case SDL_FINGERUP:
		if (e.type == SDL_FINGERMOTION)
			lua_pushstring(L, "fingermotion");
		else
			lua_pushstring(L, (e.type == SDL_FINGERDOWN)?"fingerdown":"fingerup");
		lua_pushinteger(L, e.tfinger.touchId);
		lua_pushinteger(L, e.tfinger.fingerId);
		lua_pushnumber(L, e.tfinger.x);
		lua_pushnumber(L, e.tfinger.y);
		return 5;
	case SDL_WINDOWEVENT:
		if (e.window.event == SDL_WINDOWEVENT_RESIZED) {
			lua_pushstring(L, "resized");
			lua_pushinteger(L, e.window.data1);
			lua_pushinteger(L, e.window.data2);
			WindowResize(e.window.data1, e.window.data2);
			return 3;
		} else if (e.window.event == SDL_WINDOWEVENT_EXPOSED ||
			e.window.event == SDL_WINDOWEVENT_RESTORED) {
			lua_pushstring(L, "exposed");
			return 1;
		}
		/* on some systems, when alt-tabbing to the window SDL will queue up
		** several KEYDOWN events for the `tab` key; we flush all keydown
		** events on focus so these are discarded */
		if (e.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
			SDL_FlushEvent(SDL_KEYDOWN);
			SDL_FlushEvent(SDL_KEYUP);
		}
		goto top;
	case SDL_CONTROLLERBUTTONDOWN:
		lua_pushstring(L, "keydown");
		lua_pushstring(L, gamepad_key(e.cbutton.button));
		return 2;
	case SDL_CONTROLLERBUTTONUP:
		lua_pushstring(L, "keyup");
		lua_pushstring(L, gamepad_key(e.cbutton.button));
		return 2;
	case SDL_KEYDOWN:
		lua_pushstring(L, "keydown");
		lua_pushstring(L, key_name(e.key.keysym.scancode));
		return 2;
	case SDL_KEYUP:
		lua_pushstring(L, "keyup");
		lua_pushstring(L, key_name(e.key.keysym.scancode));
		return 2;
	case SDL_TEXTINPUT:
		lua_pushstring(L, "text");
		lua_pushstring(L, e.text.text);
		return 2;
#ifdef __ANDROID__
	case SDL_TEXTEDITING:
		if (e.text.text[0] && e.text.text[strlen(e.text.text) - 1] == '\001') { /* more */
			e.text.text[strlen(e.text.text) - 1] = 0;
			if (strlen(edit_str) + strlen(e.text.text) + 1 < sizeof(edit_str))
				strcat(edit_str, e.text.text);
			goto top;
		}
		strcat(edit_str, e.text.text);
		lua_pushstring(L, "edit");
		lua_pushstring(L, edit_str);
		edit_str[0] = 0;
		return 2;
#endif
	case SDL_MOUSEBUTTONDOWN:
		if (e.button.button == 1) { SDL_CaptureMouse(1); }
		lua_pushstring(L, "mousedown");
		lua_pushstring(L, button_name(e.button.button));
		lua_pushinteger(L, scalew*e.button.x);
		lua_pushinteger(L, scaleh*e.button.y);
		lua_pushinteger(L, e.button.clicks);
		return 5;
	case SDL_MOUSEBUTTONUP:
		if (e.button.button == 1) { SDL_CaptureMouse(0); }
		lua_pushstring(L, "mouseup");
		lua_pushstring(L, button_name(e.button.button));
		lua_pushinteger(L, scalew*e.button.x);
		lua_pushinteger(L, scaleh*e.button.y);
		return 4;
	case SDL_MOUSEMOTION:
		lua_pushstring(L, "mousemotion");
		int x = e.motion.x;
		int y = e.motion.y;
		int xrel = e.motion.xrel;
		int yrel = e.motion.yrel;
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_MOUSEMOTION, SDL_MOUSEMOTION) > 0) {
			x = e.motion.x;
			y = e.motion.y;
			xrel += e.motion.xrel;
			yrel += e.motion.yrel;
		}
		lua_pushinteger(L, scalew*x);
		lua_pushinteger(L, scaleh*y);
		lua_pushinteger(L, scalew*xrel);
		lua_pushinteger(L, scaleh*yrel);
		return 5;
	case SDL_MOUSEWHEEL:
		lua_pushstring(L, "mousewheel");
		int my = e.wheel.y;
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_MOUSEWHEEL, SDL_MOUSEWHEEL) > 0) {
			my = my + e.wheel.y;
		}
		lua_pushinteger(L, my);
		return 2;
	case SDL_USEREVENT:
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_USEREVENT, SDL_USEREVENT) > 0);
		lua_pushstring(L, "wake");
		return 1;
	default:
		goto top;
	}
	return 0;
}

#define MAX_HANDLES 32

struct handles {
	int fd_nr;
	int fd_pos;
	int fd_size;
	void *fds[MAX_HANDLES];
};
#define HAN_INIT { 0, 0, MAX_HANDLES, { NULL, }}

static int
han_open(struct handles *h, void *data)
{
	int i, fd;
	if (h->fd_nr >= h->fd_size)
		return -1;
	if (!data)
		return 0;
	for (i = 0; i < h->fd_size; i ++) {
		fd = (i + h->fd_pos)%(h->fd_size);
		if (!h->fds[fd]) {
			h->fd_nr ++;
			h->fd_pos = fd;
			h->fds[fd] = data;
			return fd;
		}
	}
	return -1;
}

static void*
han_get(struct handles *h, int fd)
{
	if (fd >= h->fd_size || fd < 0)
		return NULL;
	return h->fds[fd];
}

static void*
han_close(struct handles *h, int fd)
{
	void *data;
	if (fd >= h->fd_size || fd < 0)
		return NULL;
	if (!h->fds[fd])
		return NULL;
	data = h->fds[fd];
	h->fds[fd] = NULL;
	h->fd_nr --;
	h->fd_pos = fd;
	return data;
}

static struct handles mutexes = HAN_INIT;

int
MutexDestroy(int id)
{
	SDL_mutex *m = han_close(&mutexes, id);
	if (!m)
		return -1;
	SDL_DestroyMutex(m);
	return 0;
}

int
MutexLock(int id)
{
	SDL_mutex *m = han_get(&mutexes, id);
	if (!m)
		return -1;
	return SDL_LockMutex(m);
}

int
MutexUnlock(int id)
{
	SDL_mutex *m = han_get(&mutexes, id);
	if (!m)
		return -1;
	return SDL_UnlockMutex(m);
}

int
Mutex(void)
{
	int fd;
	SDL_mutex *m = SDL_CreateMutex();
	if (!m)
		return -1;
	if ((fd = han_open(&mutexes, m)) < 0) {
		SDL_DestroyMutex(m);
		return -1;
	}
	return fd;
}

static struct handles sems = HAN_INIT;

int
SemWait(int id, int ms)
{
	SDL_sem *sem = han_get(&sems, id);
	if (!sem)
		return -1;
	return SDL_SemWaitTimeout(sem, ms);
}

int
Sem(int counter)
{
	int fd;
	SDL_sem *sem = SDL_CreateSemaphore(counter);
	if (!sem)
		return -1;
	fd = han_open(&sems, sem);
	if (fd < 0) {
		SDL_DestroySemaphore(sem);
		return -1;
	}
	return fd;
}

int
SemPost(int id)
{
	SDL_sem *sem = han_get(&sems, id);
	if (!sem)
		return -1;
	return SDL_SemPost(sem);
}

int
SemDestroy(int id)
{
	SDL_sem *sem = han_close(&sems, id);
	if (!sem)
		return -1;
	SDL_DestroySemaphore(sem);
	return 0;
}

static struct handles threads = HAN_INIT;

int
ThreadWait(int id)
{
	int status;
	SDL_Thread *thread = han_get(&threads, id);
	if (!thread)
		return -1;
	SDL_WaitThread(thread, &status);
	han_close(&threads, id);
	return status;
}

void
ThreadDetach(int id)
{
	SDL_Thread *thread = han_get(&threads, id);
	if (!thread)
		return;
	SDL_DetachThread(thread);
	han_close(&threads, id);
	return;
}

int
Thread(int (*fn) (void *), void *data)
{
	int fd;
	SDL_Thread *thread;
	fd = han_open(&threads, NULL);
	if (fd < 0)
		return -1;
	thread = SDL_CreateThread(fn, NULL, data);
	if (!thread)
		return -1;
	return han_open(&threads, thread);
}
static int
sock_err(int r)
{
	if (r >= 0)
		return 0;
#if defined(_WIN32)
	int e = WSAGetLastError();
	switch (e) {
	case WSAEWOULDBLOCK:
		return EWOULDBLOCK;
	case WSAENOTCONN:
	case WSAEINPROGRESS:
		return EINPROGRESS;
	case WSAEINTR:
		return EINTR;
	case WSAENOBUFS:
		return ENOBUFS;
	default:
		return EINVAL;
	}
#else
	return errno;
#endif
}
static void
nonblock(int fd)
{
#if defined(O_NONBLOCK)
	fcntl(fd, F_SETFL, O_NONBLOCK);
#elif defined(_WIN32)
	{
		unsigned long mode = 1;
		ioctlsocket(fd, FIONBIO, &mode);
	}
#endif
#ifdef TCP_NODELAY
	{
		int yes = 1;
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (char*)&yes, sizeof(yes));
	}
#endif
}

int
Dial(const char *host, const char *port)
{
	int fd;
	struct addrinfo hints;
	struct addrinfo *res, *r;
	memset(&hints, 0, sizeof hints);
#ifdef AI_ADDRCONFIG
	hints.ai_flags = AI_ADDRCONFIG;
	hints.ai_family = AF_UNSPEC;
#else
	hints.ai_family = AF_INET;
#endif
	hints.ai_socktype = SOCK_STREAM;

	if (getaddrinfo(host, port, &hints, &res))
		return -1;

	for (r = res; r; r = r->ai_next) {
		if ((fd = socket(r->ai_family, r->ai_socktype, r->ai_protocol)) < 0)
			continue;
		#ifndef _WIN32
		nonblock(fd);
		#endif
		if (!connect(fd, r->ai_addr, r->ai_addrlen) ||
			sock_err(-1) == EINPROGRESS || sock_err(-1) == EWOULDBLOCK) {
			break;
		}
		Shutdown(fd);
	}
	freeaddrinfo(res);
	if (!r)
		return -1;
	#ifdef _WIN32
	nonblock(fd);
	#endif
	return fd;
}

int
Send(int fd, const void *data, int size)
{
	int rc, err;
	rc = send(fd, (const char *)data, (size_t)size, 0);
	err = sock_err(rc);
	if (rc < 0 && (err == EAGAIN || err == EWOULDBLOCK ||
		err == EINPROGRESS || err == ENOTCONN))
		return 0;
	return rc;
}

int
Recv(int fd, void *data, int size)
{
	int rc, err;
	rc = recv(fd, data, size, 0);
	if (rc == 0) /* closed */
		return -1;
	err = sock_err(rc);
	if (rc < 0 && (err == EAGAIN ||
		err == EWOULDBLOCK || err == ENOENT ||
		err == EINPROGRESS))
		return 0;
	return rc;
}

void
Shutdown(int fd)
{
#ifdef _WIN32
	closesocket(fd);
#else
	close(fd);
#endif
}

char *
Clipboard(const char *text)
{
	char *c = NULL, *p;
	if (!text) { /* get */
#if SDL_VERSION_ATLEAST(2, 26, 0)
		if (opt_xclip && SDL_HasPrimarySelectionText())
			c = SDL_GetPrimarySelectionText();
		if (opt_xclip > 1)
			goto skip;
#endif
		if (!c && !SDL_HasClipboardText())
			return NULL;
		if (!c)
			c = SDL_GetClipboardText();
#if SDL_VERSION_ATLEAST(2, 26, 0)
skip:
#endif
		if (!c)
			return NULL;
		p = strdup(c);
		SDL_free(c);
		return p;
	}
#if SDL_VERSION_ATLEAST(2, 26, 0)
	if (opt_xclip) {
		SDL_SetPrimarySelectionText(text);
		if (opt_xclip > 1)
			return NULL;
	}
#endif
	SDL_SetClipboardText(text);
	return NULL;
}

int
IsAbsolutePath(const char *path)
{
	if (!path || !*path)
		return 0;
#ifndef _WIN32
	return (*path == '/');
#else
	return (*path == '/' || *path == '\\' || path[1] == ':');
#endif
}

/*
 * char *realpath(const char *path, char *resolved);
 *
 * Find the real name of path, by removing all ".", ".." and symlink
 * components.  Returns (resolved) on success, or (NULL) on failure,
 * in which case the path which caused trouble is left in (resolved).
 */
char *
GetRealpath(const char *path)
{
	char *resolved;
	const char *q;
	char *p;
	size_t len;

	/* POSIX sez we must test for this */
	if (path == NULL) {
		return NULL;
	}

	resolved = malloc(PATH_MAX);
	if (resolved == NULL)
		return NULL;

	/*
	 * Build real path one by one with paying an attention to .,
	 * .. and symbolic link.
	 */

	/*
	 * `p' is where we'll put a new component with prepending
	 * a delimiter.
	 */
	p = resolved;

	if (*path == '\0') {
		*p = '\0';
		goto out;
	}

	/* If relative path, start from current working directory. */
	if (!IsAbsolutePath(path)) {
		/* check for resolved pointer to appease coverity */
		if (getcwd(resolved, PATH_MAX) == NULL) {
			p[0] = '.';
			p[1] = '\0';
			goto out;
		}
		unix_path(resolved);
		len = strlen(resolved);
		if (len > 1) {
			p += len;
			while (p != resolved && *(p-1) == '/')
				*(--p) = 0;
		}
	}

loop:
	/* Skip any slash. */
	while (*path == '/')
		path++;

	if (*path == '\0') {
		if (p == resolved)
			*p++ = '/';
		*p = '\0';
		return resolved;
	}

	/* Find the end of this component. */
	q = path;
	do
		q++;
	while (*q != '/' && *q != '\0');

	/* Test . or .. */
	if (path[0] == '.') {
		if (q - path == 1) {
			path = q;
			goto loop;
		}
		if (path[1] == '.' && q - path == 2) {
			/* Trim the last component. */
			if (p != resolved)
				while (*--p != '/' && p != resolved)
					continue;
			path = q;
			goto loop;
		}
	}

	/* Append this component. */
	if (p - resolved + 1 + q - path + 1 > PATH_MAX) {
		if (p == resolved)
			*p++ = '/';
		*p = '\0';
		goto out;
	}
	if (p == resolved
		&& IsAbsolutePath(path)
			&& path[0] != '/') { /* win? */
		memcpy(&p[0], path,
		    q - path);
		p[q - path] = '\0';
		p += q - path;
		path = q;
		goto loop;
	} else {
		p[0] = '/';
		memcpy(&p[1], path,
		    /* LINTED We know q > path. */
		    q - path);
		p[1 + q - path] = '\0';
	}
	/* Advance both resolved and unresolved path. */
	p += 1 + q - path;
	path = q;
	goto loop;
out:
	free(resolved);
	return NULL;
}
