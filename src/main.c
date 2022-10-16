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

	(void) luaL_dostring(L,
			     "local core\n"
			     "xpcall(function()\n"
			     "  PATHSEP = package.config:sub(1, 1)\n"
			     "  package.path = DATADIR .. '/core/?.lua;' .. package.path\n"
			     "  core = require('core')\n"
			     "  core.init()\n"
			     "  core.run()\n"
			     "end, function(err)\n"
			     "  print('Error: ' .. tostring(err))\n"
			     "  print(debug.traceback(nil, 2))\n"
			     "  if core and core.on_error then\n"
			     "    pcall(core.on_error, err)\n"
			     "  end\n"
			     "  os.exit(1)\n"
			     "end)");
	lua_close(L);
	PlatformDone();
	return 0;
}
