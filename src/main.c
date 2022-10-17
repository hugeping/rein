#include "external.h"
#include "platform.h"
#include "gfx.h" /* to get font_renderer */
extern int system_init(lua_State *L);

static int
luaopen_system(lua_State *L)
{
	system_init(L);
	return 1;
}

extern int gfx_init(lua_State *L);

int
luaopen_gfx(lua_State *L)
{
	gfx_init(L);
	return 1;
}

static const luaL_Reg lua_libs[] = {
	{ "system",    luaopen_system },
	{ "gfx",  luaopen_gfx },
	{ NULL, NULL }
};

#if defined(_WIN32) || defined(PLAN9) || defined(__ANDROID__)
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
#endif

void unix_path(char *path)
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

static int
report(lua_State *L, int status)
{
	const char *msg;
	if (!status || lua_isnil(L, -1))
		return 0;
	msg = lua_tostring(L, -1);
	if (msg)
		fprintf(stderr,"%s\n", msg);
	lua_pop(L, 1);
	return status;
}

static int traceback (lua_State *L)
{
#if LUA_VERSION_NUM >= 502
	lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS);
	lua_getfield(L, -1, "debug");
#else
	lua_getfield(L, LUA_GLOBALSINDEX, "debug");
#endif
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return 1;
	}
	lua_getfield(L, -1, "traceback");
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 2);
		return 1;
	}
	lua_pushvalue(L, 1);  /* pass error message */
	lua_pushinteger(L, 2);  /* skip this function and traceback */
	lua_call(L, 2, 1);  /* call debug.traceback */
	return 1;
}

static int
docall(lua_State *L)
{
	int rc;
	int base;
	base = lua_gettop(L);
	lua_pushcfunction(L, traceback);
	lua_insert(L, base);
	rc = lua_pcall(L, 0, LUA_MULTRET, base);
	lua_remove(L, base);
	if (rc != 0)
		lua_gc(L, LUA_GCCOLLECT, 0);
	return report(L, rc);
}

static int
dostring(lua_State *L, const char *s)
{
	int rc = luaL_loadstring(L, s);
	if (rc)
		return rc;
	return docall(L);
}

static int
cycle(lua_State *L)
{
	int rc;
	lua_getglobal(L, "core");
	lua_getfield(L, -1, "run");
	lua_remove(L, -2);
	if (docall(L))
		return -1;
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
	char *exepath;
	static char base[4096];
	int i;

	lua_State *L = luaL_newstate();
	if (!L)
		return 1;

	if (PlatformInit()) {
		fprintf(stderr, "Can not do platform init!\n");
		return 1;
	}

	luaL_openlibs(L);
	lua_newtable(L);
	for (i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i + 1);
	}
	lua_setglobal(L, "ARGS");

	lua_pushstring(L, GetPlatform());
	lua_setglobal(L, "PLATFORM");

	lua_pushnumber(L, GetScale());
	lua_setglobal(L, "SCALE");

	if (WindowCreate()) {
		fprintf(stderr, "Can not create window!\n");
		return 1;
	}

	for (i = 0; lua_libs[i].name; i++)
		luaL_requiref(L, lua_libs[i].name, lua_libs[i].func, 1);

	exepath = strdup(GetExePath(argv[0]));
	unix_path(exepath);

	lua_pushstring(L, exepath);
	lua_setglobal(L, "EXEFILE");

	lua_pushstring(L, font_renderer());
	lua_setglobal(L, "FONTRENDERER");

#ifdef __ANDROID__
	snprintf(base, sizeof(base), "%s", SDL_AndroidGetInternalStoragePath());
#else
	snprintf(base, sizeof(base), "%s/%s", dirname((char*)exepath), "data");
#endif
#ifdef DATADIR
	lua_pushstring(L, DATADIR);
#else
	lua_pushstring(L, base);
#endif
	lua_setglobal(L, "DATADIR");

#if defined(_WIN32) || defined(PLAN9) || defined(__ANDROID__)
	#ifdef __ANDROID__
	snprintf(base, sizeof(base), "%s/%s", SDL_AndroidGetInternalStoragePath(), "errors.txt");
	#else
	snprintf(base, sizeof(base), "%s/%s", exepath, "errors.txt");
	#endif

	#if defined(_WIN32)
	if (GetStdHandle(STD_OUTPUT_HANDLE) == NULL) {
	#else
	if (1) {
	#endif
		reopen_stderr(base);
		reopen_stdout(base);
	}
#endif
	free(exepath);

	dostring(L, "PATHSEP = package.config:sub(1, 1)\n"
		"  package.path = DATADIR .. '/core/?.lua;' .. package.path\n"
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
	PlatformDone();
	return 0;
}
