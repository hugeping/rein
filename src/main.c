#include "external.h"
#include "platform.h"

#ifndef VERSION
#define VERSION "unknown"
#endif

extern int luaopen_bit(lua_State *L);
extern int luaopen_system(lua_State *L);
extern int luaopen_thread(lua_State *L);
extern int luaopen_gfx(lua_State *L);
extern int luaopen_utf(lua_State *L);
extern int luaopen_net(lua_State *L);
extern int luaopen_synth(lua_State *L);

extern int synth_init(void);
extern void synth_done(void);

static const luaL_Reg lua_libs[] = {
	{ "sys", luaopen_system },
	{ "utf", luaopen_utf },
	{ "gfx", luaopen_gfx },
	{ "bit", luaopen_bit },
	{ "thread", luaopen_thread },
	{ "net", luaopen_net },
	{ "synth", luaopen_synth },
	{ NULL, NULL }
};

#if defined(_WIN32) || defined(__ANDROID__)
static void
reopen_stderr(const char *fname)
{
	if (*fname && freopen(fname, "w", stderr) != stderr) {
		fprintf(stderr, "Error opening '%s': %s\n", fname, strerror(errno));
		exit(1);
	}
}
static void
reopen_stdout(const char *fname)
{
	if (*fname && freopen(fname, "w", stdout) != stdout) {
		fprintf(stderr, "Error opening '%s': %s\n", fname, strerror(errno));
		exit(1);
	}
}
static void
base_path(char *base, size_t size, const char *exepath, const char *file)
{
	#ifdef __ANDROID__
	snprintf(base, size, "%s/%s", SDL_AndroidGetInternalStoragePath(), file);
	#else
	snprintf(base, size, "%s/%s", exepath, file);
	#endif
}
#endif

static int
dostring(lua_State *L, const char *s)
{
	int rc = luaL_loadstring(L, s);
	if (rc)
		return rc;
	rc = lua_callfn(L);
	if (rc)
		lua_pop(L, 1);
	return rc;
}

static int
cycle(lua_State *L)
{
	int rc;
	lua_getglobal(L, "core");
	lua_getfield(L, -1, "run");
	lua_remove(L, -2);
	if (lua_callfn(L)) {
		lua_pop(L, 1);
		return -1;
	}
	rc = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return !rc;
}

#ifdef __EMSCRIPTEN__
static lua_State *LL;

static void
void_cycle(void)
{
	if (cycle(LL)) {
		dostring(LL, "core.done()");
		emscripten_cancel_main_loop();
		emscripten_force_exit(1);
	}
}
#endif


int
main(int argc, char **argv)
{
	char *exepath, *exedir;
	const char *exefile;
	static char base[4096];
	int i;

	exefile = GetExePath(argv[0]);
	exepath = strdup(exefile);
	exedir = dirname(exepath);

	lua_State *L = luaL_newstate();
	if (!L)
		return 1;
#ifdef DATADIR
	lua_pushstring(L, DATADIR);
#else
	#ifdef __ANDROID__
	snprintf(base, sizeof(base), "%s", SDL_AndroidGetInternalStoragePath());
	#else
	snprintf(base, sizeof(base), "%s/%s", exedir, "data");
	#endif
	lua_pushstring(L, base);
#endif
	lua_setglobal(L, "DATADIR");
	lua_pushstring(L, VERSION);
	lua_setglobal(L, "VERSION");
#if defined(_WIN32) || defined(__ANDROID__)
	#if defined(_WIN32)
	if (GetStdHandle(STD_OUTPUT_HANDLE) == NULL) {
	#else
	if (1) {
	#endif
		base_path(base, sizeof(base), exedir, "log.txt");
		reopen_stdout(base);
		base_path(base, sizeof(base), exedir, "err.txt");
		reopen_stderr(base);
	}
#endif

	if (PlatformInit()) {
		fprintf(stderr, "Can not do platform init!\n");
		return 1;
	}
	synth_init();
	luaL_openlibs(L);
	lua_newtable(L);
	for (i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i + 1);
	}
	lua_setglobal(L, "ARGS");

	lua_pushstring(L, GetPlatform());
	lua_setglobal(L, "PLATFORM");

	lua_pushstring(L, GetLanguage());
	lua_setglobal(L, "LANGUAGE");

	lua_pushnumber(L, GetScale());
	lua_setglobal(L, "SCALE");

	if (WindowCreate()) {
		fprintf(stderr, "Can not create window!\n");
		return 1;
	}

	for (i = 0; lua_libs[i].name; i++)
		luaL_requiref(L, lua_libs[i].name, lua_libs[i].func, 1);

	lua_pushstring(L, exepath);
	lua_setglobal(L, "EXEFILE");

	free(exepath);

	dostring(L, "PATHSEP = package.config:sub(1, 1)\n"
		"  package.path = DATADIR .. '/core/?.lua;' .. DATADIR .. '/lib/?.lua;' .. package.path\n"
		"  core = require('core')\n"
		"  core.init()\n");
#if __EMSCRIPTEN__
	LL = L;
	emscripten_set_main_loop(void_cycle, 0, 0);
	return 0;
#else
	while (!cycle(L));
#endif
	dostring(L, "core.done()");

	lua_close(L);
	synth_done();
	PlatformDone();
	return 0;
}
