#include <SDL.h>
#include "external.h"
#include "platform.h"

#ifdef __ANDROID__
#include <jni.h>
#include <android/log.h>
#define LOG(s) do { __android_log_print(ANDROID_LOG_VERBOSE, "reinstead", "%s", s); } while(0)
#else
#define LOG(s) do { printf("%s\n", (s)); } while(0)
#endif

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
static SDL_RendererInfo renderer_info;

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

int
WaitEvent(float n)
{
#ifdef __EMSCRIPTEN__
	return 1;
#else
/* standard function may sleep longer than 20ms (in Windows) */
//	if (n >= 0.05f)
//		return SDL_WaitEventTimeout(NULL, (int)(n * 1000));
//	else
		return SDL_WaitEventTo((int)(n * 1000));
#endif
}

void
Delay(float n)
{
#if !defined(__EMSCRIPTEN__)
	SDL_Delay(n * 1000);
#endif
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
	if (SDL_GetDisplayDPI(0, NULL, &dpi, NULL))
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
	unsigned int readed = audio_read(stream, len);
	if (readed < len)
		memset(stream + readed, 0, len - readed);
}

void
MouseHide(int off)
{
	SDL_ShowCursor(!off?SDL_ENABLE:SDL_DISABLE);
}

int
PlatformInit(void)
{
	SDL_AudioSpec spec;
#ifdef _WIN32
	int (*SetProcessDPIAware)();
	user32_lib = LoadLibrary("user32.dll");
	SetProcessDPIAware = (void*) GetProcAddress(user32_lib, "SetProcessDPIAware");
	if (SetProcessDPIAware)
		SetProcessDPIAware();
#endif
	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_AUDIO))
		return -1;
	spec.freq = 44100;
	spec.format = AUDIO_S16;
	spec.channels = 2;
	spec.samples = 2048 * spec.channels;
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
	return 0;
}

static SDL_Surface *winbuff = NULL;

void
PlatformDone(void)
{
	SDL_PauseAudioDevice(audiodev, 1);
	if (audiodev)
		SDL_CloseAudioDevice(audiodev);
#ifdef _WIN32
	if (user32_lib)
		FreeLibrary(user32_lib);
#endif
	if (winbuff)
		SDL_FreeSurface(winbuff);
	if (texture)
		SDL_DestroyTexture(texture);
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

int
WindowCreate(void)
{
	SDL_DisplayMode mode;
	SDL_GetCurrentDisplayMode(0, &mode);
	if (SDL_CreateWindowAndRenderer(mode.w * 0.5, mode.h * 0.8,
		SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI, &window, &renderer))
		return -1;
	SDL_GetRendererInfo(renderer, &renderer_info);
	fprintf(stderr, "Video: %s%s\n", renderer_info.name,
		(renderer_info.flags & SDL_RENDERER_ACCELERATED)?" (accelerated)":"");
	SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
	return 0;
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
	if (renderer_info.flags & SDL_RENDERER_ACCELERATED)
	    w = -1;
	if (w > 0 && h > 0) {
		rect.x = x;
		rect.y = y;
		rect.w = w;
		rect.h = h;
		pixels += pitch * y + x * psize;
		SDL_UpdateTexture(texture, &rect, pixels, pitch);
		SDL_RenderCopy(renderer, texture, &rect, &rect);
	} else {
		SDL_UpdateTexture(texture, NULL, pixels, pitch);
		SDL_RenderClear(renderer);
		SDL_RenderCopy(renderer, texture, NULL, NULL);
		if (destroyed) { /* problem with double buffering */
			SDL_RenderPresent(renderer);
			SDL_UpdateTexture(texture, NULL, pixels, pitch);
			SDL_RenderClear(renderer);
			SDL_RenderCopy(renderer, texture, NULL, NULL);
		}
	}
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
	SDL_GetWindowSize(window, w, h);
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
		lua_pushinteger(L, e.button.x);
		lua_pushinteger(L, e.button.y);
		lua_pushinteger(L, e.button.clicks);
		return 5;
	case SDL_MOUSEBUTTONUP:
		if (e.button.button == 1) { SDL_CaptureMouse(0); }
		lua_pushstring(L, "mouseup");
		lua_pushstring(L, button_name(e.button.button));
		lua_pushinteger(L, e.button.x);
		lua_pushinteger(L, e.button.y);
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
		lua_pushinteger(L, x);
		lua_pushinteger(L, y);
		lua_pushinteger(L, xrel);
		lua_pushinteger(L, yrel);
		return 5;
	case SDL_MOUSEWHEEL:
		lua_pushstring(L, "mousewheel");
		int my = e.wheel.y;
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_MOUSEWHEEL, SDL_MOUSEWHEEL) > 0) {
			my = my + e.wheel.y;
		}
		lua_pushinteger(L, my);
		return 2;
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
