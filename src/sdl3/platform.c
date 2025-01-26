#include <SDL3/SDL.h>
#include <SDL3/SDL_gamepad.h>
#include "../external.h"
#include "../platform.h"

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
static SDL_Texture *expose_texture = NULL;

static float scalew = 1.0f, scaleh = 1.0f;

void
Log(const char *msg)
{
	LOG(msg);
}

void
TextInput(void)
{
	SDL_StartTextInput(window);
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
		n == WIN_FULLSCREEN ? SDL_WINDOW_FULLSCREEN : 0);
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

#ifdef _WIN32
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
	event.type = SDL_EVENT_USER;
	SDL_PushEvent(&event);
	return;
}

int
WaitEvent(float n)
{
#ifdef _WIN32
/* standard function may sleep longer than 20ms (in Windows) */
	return SDL_WaitEventTo((int)(n * 1000));
#else
	return SDL_WaitEventTimeout(NULL, (int)(n * 1000));
#endif
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
	case SDL_GAMEPAD_BUTTON_DPAD_UP:
		key = "up";
		break;
	case SDL_GAMEPAD_BUTTON_DPAD_DOWN:
		key = "down";
		break;
	case SDL_GAMEPAD_BUTTON_DPAD_LEFT:
		key = "left";
		break;
	case SDL_GAMEPAD_BUTTON_DPAD_RIGHT:
		key = "right";
		break;
	case SDL_GAMEPAD_BUTTON_SOUTH:
		key = "z";
		break;
	case SDL_GAMEPAD_BUTTON_EAST:
		key = "x";
		break;
	case SDL_GAMEPAD_BUTTON_WEST:
		key = "c";
		break;
	case SDL_GAMEPAD_BUTTON_NORTH:
		key = "space";
		break;
	case SDL_GAMEPAD_BUTTON_START:
		key = "escape";
		break;
	case SDL_GAMEPAD_BUTTON_LEFT_SHOULDER:
		key = "left shift";
		break;
	case SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER:
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
	return SDL_GetWindowDisplayScale(window);
#endif
}

#ifdef _WIN32
static HINSTANCE user32_lib;
#endif

static SDL_AudioStream *audiostream;

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
	if (!audiostream)
		return size;
	SDL_LockAudioStream(audiostream);
	if (!data) { /* get avail space */
		rc = audiobuff.free;
		SDL_UnlockAudioStream(audiostream);
		return rc;
	}
	towrite = (size >= audiobuff.free)?audiobuff.free:size;
	pos = audiobuff.tail;
	audiobuff.free -= towrite;
	rc = towrite;
	while (towrite--)
		audiobuff.data[pos++ % audiobuff.size] = *(buf ++);
	audiobuff.tail = pos % audiobuff.size;
	SDL_UnlockAudioStream(audiostream);
	return rc;
}

static void
audio_read(SDL_AudioStream *stream, int len)
{
	unsigned int used, toread;
//	SDL_LockAudioStream(stream);
	used = audiobuff.size - audiobuff.free;
	toread = (used<=len)?used:len;
//	if (toread < len)
//		SDL_PutAudioStreamData(SDL_AudioStream *stream, const void *buf, int len);
//		memset(stream + toread, 0, (len - toread));
	audiobuff.free += toread;
	while (toread) {
		int chunk_sz = audiobuff.size - audiobuff.head;
		if (toread <= chunk_sz)
			chunk_sz = toread;
		SDL_PutAudioStreamData(stream, audiobuff.data + audiobuff.head, chunk_sz);
		audiobuff.head += chunk_sz;
		toread -= chunk_sz;
		audiobuff.head %= audiobuff.size;
	}
	SDL_FlushAudioStream(stream);
}

static void
audio_cb(void *userdata, SDL_AudioStream *stream, int additional_amount, int len)
{
	audio_read(stream, len);
}

void
MouseHide(int off)
{
	if (off)
		SDL_HideCursor();
	else
		SDL_ShowCursor();
}

static SDL_Gamepad *gamepad = NULL;

static void
gamepad_init(void)
{
	int i;
	int num_joysticks = 0;
	SDL_JoystickID *joysticks_list = NULL;

	if (opt_nojoystick)
		return;

	if (!SDL_InitSubSystem(SDL_INIT_GAMEPAD)) {
		fprintf(stderr, "Couldn't initialize GameController subsystem: %s\n", SDL_GetError());
		return;
	}

	joysticks_list = SDL_GetGamepads(&num_joysticks);

	for (i = 0; i < num_joysticks; ++i) {
		gamepad = SDL_OpenGamepad(joysticks_list[i]);
		if (gamepad) {
			fprintf(stdout, "Found gamepad: %s\n",
				SDL_GetGamepadName(gamepad));
			break;
		} else {
			fprintf(stderr, "Could not open gamepad %i: %s\n",
				i, SDL_GetError());
		}
	}
	SDL_free(joysticks_list);
}

static void
gamepad_done(void)
{
	if(gamepad)
		SDL_CloseGamepad(gamepad);
	if(SDL_WasInit(SDL_INIT_GAMEPAD))
		SDL_QuitSubSystem(SDL_INIT_GAMEPAD);
}

static void
sound_init(void)
{
	SDL_AudioSpec spec;
	if (opt_nosound)
		return;
	if (!SDL_InitSubSystem(SDL_INIT_AUDIO)) {
		fprintf(stderr, "Couldn't initialize Audio subsystem: %s\n", SDL_GetError());
		return;
	}
	spec.freq = 44100;
	spec.format = SDL_AUDIO_S16;
	spec.channels = 2;

	audiostream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_cb, NULL);
	if (audiostream) {
		printf("Audio: %dHz channels: %d\n",
			spec.freq, spec.channels);
		audiobuff.size = 4096;
		audiobuff.free = audiobuff.size;
		audiobuff.data = malloc(audiobuff.size);
		audiobuff.head = 0;
		audiobuff.tail = 0;
	} else {
		fprintf(stderr, "No audio: %s\n", SDL_GetError());
	}
	SDL_ResumeAudioStreamDevice(audiostream);
}

static void
sound_done(void)
{
	SDL_PauseAudioStreamDevice(audiostream);
	if (audiostream)
		SDL_DestroyAudioStream(audiostream);
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
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
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

	if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS))
		return -1;
	sound_init();
	gamepad_init();
	return 0;
}

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
	SDL_Locale **l = SDL_GetPreferredLocales(NULL);
	if (l) {
		snprintf(b, 16, "%s", l[0] && l[0]->language ? l[0]->language : "");
		SDL_free(l);
	}
	return b;
}


int
WindowCreate(void)
{
	const SDL_DisplayMode *mode;
	int disp_nr = 0;
	SDL_DisplayID *disp_list = SDL_GetDisplays(&disp_nr);
	if (!disp_list)
		return -1;
	mode = SDL_GetCurrentDisplayMode(disp_list[0]);
	SDL_free(disp_list);
	if (!mode)
		return -1;
	if (!SDL_CreateWindowAndRenderer("rein", (int)(mode->w * 0.5), (int)(mode->h * 0.8),
#ifdef __EMSCRIPTEN__
		SDL_WINDOW_RESIZABLE, &window, &renderer))
#else
		SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY, &window, &renderer))
#endif
		return -1;
#ifndef __ANDROID__
	SDL_StartTextInput(window);
#endif
	fprintf(stdout, "Video: %s\n", SDL_GetRendererName(renderer));
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
WindowSize(int *w, int *h)
{
	if (window)
		SDL_GetWindowSizeInPixels(window, w, h);
}

void
WindowExpose(void *pixels, int w, int h, int pitch, int dx, int dy, int dw, int dh)
{
	SDL_Rect rect;
	SDL_FRect drect;
	SDL_FRect srect;
	static int expose_w = 0, expose_h = 0;
	if (!expose_texture || w > expose_w || h > expose_h) {
		SDL_DestroyTexture(expose_texture);
		expose_texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
			SDL_TEXTUREACCESS_STREAMING, w, h);
		if (!expose_texture)
			return;
		SDL_SetTextureScaleMode(expose_texture, SDL_SCALEMODE_NEAREST);
		expose_w = w; expose_h = h;
	}
	rect.x = 0; rect.y = 0;
	rect.w = w; rect.h = h;
	SDL_UpdateTexture(expose_texture, &rect, pixels, pitch);
	if (dx || dy || dw > 0 || dh > 0) {
		srect.x = 0; srect.y = 0;
		srect.w = w; srect.h = h;
		drect.x = dx; drect.y = dy;
		if (dw <= 0 || dh <= 0)
			SDL_GetCurrentRenderOutputSize(renderer, &dw, &dh);
		drect.w = dw;
		drect.h = dh;
		SDL_RenderTexture(renderer, expose_texture, &srect, &drect);
	} else
		SDL_RenderTexture(renderer, expose_texture, &srect, NULL);
}

unsigned int
GetMouse(int *ox, int *oy)
{
	Uint32 mb;
	float x, y;
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
WindowClear(int r, int g, int b)
{
	SDL_SetRenderDrawColor(renderer, r, g, b, 255);
	SDL_RenderClear(renderer);
}

void
Flip(void)
{
	if (window) {
		int ww, wh, rw, rh;
		SDL_GetWindowSize(window, &ww, &wh);
		SDL_GetCurrentRenderOutputSize(renderer, &rw, &rh);
		scalew = (float)rw/ww, scaleh = (float)rh/wh;
	}
	SDL_RenderPresent(renderer);
}

void
Icon(unsigned char *ptr, int w, int h)
{
	SDL_Surface *surf;
	surf = SDL_CreateSurfaceFrom(w, h,
			SDL_PIXELFORMAT_RGBA32,
			ptr, w * 4);
	if (!surf)
		return;
	SDL_SetWindowIcon(window, surf);
	SDL_DestroySurface(surf);
	return;
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
	case SDL_EVENT_DID_ENTER_BACKGROUND:
		lua_pushstring(L, "save");
		return 1;
	case SDL_EVENT_QUIT:
		lua_pushstring(L, "quit");
		return 1;
	case SDL_EVENT_DID_ENTER_FOREGROUND:
		lua_pushstring(L, "exposed");
		return 1;
	case SDL_EVENT_FINGER_MOTION:
	case SDL_EVENT_FINGER_DOWN:
	case SDL_EVENT_FINGER_UP:
		if (e.type == SDL_EVENT_FINGER_MOTION)
			lua_pushstring(L, "fingermotion");
		else
			lua_pushstring(L, (e.type == SDL_EVENT_FINGER_DOWN)?"fingerdown":"fingerup");
		lua_pushinteger(L, e.tfinger.touchID);
		lua_pushinteger(L, e.tfinger.fingerID);
		lua_pushnumber(L, e.tfinger.x);
		lua_pushnumber(L, e.tfinger.y);
		return 5;
//	case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
//	case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
	case SDL_EVENT_WINDOW_RESIZED:
		lua_pushstring(L, "resized");
		lua_pushinteger(L, e.window.data1);
		lua_pushinteger(L, e.window.data2);
		return 3;
	case SDL_EVENT_WINDOW_EXPOSED:
	case SDL_EVENT_WINDOW_RESTORED:
		lua_pushstring(L, "exposed");
		return 1;
	case SDL_EVENT_WINDOW_FOCUS_GAINED:
		/* on some systems, when alt-tabbing to the window SDL will queue up
		** several KEYDOWN events for the `tab` key; we flush all keydown
		** events on focus so these are discarded */
		SDL_FlushEvent(SDL_EVENT_KEY_DOWN);
		SDL_FlushEvent(SDL_EVENT_KEY_UP);
		goto top;
	case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
		lua_pushstring(L, "keydown");
		lua_pushstring(L, gamepad_key(e.gbutton.button));
		return 2;
	case SDL_EVENT_GAMEPAD_BUTTON_UP:
		lua_pushstring(L, "keyup");
		lua_pushstring(L, gamepad_key(e.gbutton.button));
		return 2;
	case SDL_EVENT_KEY_DOWN:
		lua_pushstring(L, "keydown");
		lua_pushstring(L, key_name(e.key.scancode));
		return 2;
	case SDL_EVENT_KEY_UP:
		lua_pushstring(L, "keyup");
		lua_pushstring(L, key_name(e.key.scancode));
		return 2;
	case SDL_EVENT_TEXT_INPUT:
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
	case SDL_EVENT_MOUSE_BUTTON_DOWN:
		if (e.button.button == 1) { SDL_CaptureMouse(1); }
		lua_pushstring(L, "mousedown");
		lua_pushstring(L, button_name(e.button.button));
		lua_pushinteger(L, scalew*e.button.x);
		lua_pushinteger(L, scaleh*e.button.y);
		lua_pushinteger(L, e.button.clicks);
		return 5;
	case SDL_EVENT_MOUSE_BUTTON_UP:
		if (e.button.button == 1) { SDL_CaptureMouse(0); }
		lua_pushstring(L, "mouseup");
		lua_pushstring(L, button_name(e.button.button));
		lua_pushinteger(L, scalew*e.button.x);
		lua_pushinteger(L, scaleh*e.button.y);
		return 4;
	case SDL_EVENT_MOUSE_MOTION:
		lua_pushstring(L, "mousemotion");
		int x = e.motion.x;
		int y = e.motion.y;
		int xrel = e.motion.xrel;
		int yrel = e.motion.yrel;
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_MOTION) > 0) {
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
	case SDL_EVENT_MOUSE_WHEEL:
		lua_pushstring(L, "mousewheel");
		int my = e.wheel.y;
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_EVENT_MOUSE_WHEEL, SDL_EVENT_MOUSE_WHEEL) > 0) {
			my = my + e.wheel.y;
		}
		lua_pushinteger(L, my);
		return 2;
	case SDL_EVENT_USER:
		while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_EVENT_USER, SDL_EVENT_USER) > 0);
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
	SDL_Mutex *m = han_close(&mutexes, id);
	if (!m)
		return -1;
	SDL_DestroyMutex(m);
	return 0;
}

int
MutexLock(int id)
{
	SDL_Mutex*m = han_get(&mutexes, id);
	if (!m)
		return -1;
	SDL_LockMutex(m);
	return 0;
}

int
MutexUnlock(int id)
{
	SDL_Mutex*m = han_get(&mutexes, id);
	if (!m)
		return -1;
	SDL_UnlockMutex(m);
	return 0;
}

int
Mutex(void)
{
	int fd;
	SDL_Mutex*m = SDL_CreateMutex();
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
	SDL_Semaphore *sem = han_get(&sems, id);
	if (!sem)
		return -1;
	return SDL_WaitSemaphoreTimeout(sem, ms);
}

int
Sem(int counter)
{
	int fd;
	SDL_Semaphore *sem = SDL_CreateSemaphore(counter);
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
	SDL_Semaphore *sem = han_get(&sems, id);
	if (!sem)
		return -1;
	SDL_SignalSemaphore(sem);
	return 0;
}

int
SemDestroy(int id)
{
	SDL_Semaphore *sem = han_close(&sems, id);
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
