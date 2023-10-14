#include "external.h"
#include "platform.h"
#include "gfx.h"

static int
sys_sleep(lua_State *L)
{
	float n = luaL_checknumber(L, 1);
	Delay(n);
	return 0;
}

static int
sys_wait(lua_State *L)
{
	float n = luaL_checknumber(L, 1);
	lua_pushboolean(L, WaitEvent(n));
	return 1;
}

static int
sys_title(lua_State *L)
{
	const char *title = luaL_checkstring(L, 1);
	WindowTitle(title);
	return 0;
}

static int
sys_clipboard(lua_State *L)
{
	char *p;
	const char *text = luaL_optstring(L, 1, NULL);
	if (!text) {
		p = Clipboard(NULL);
		if (p) {
			lua_pushstring(L, p);
			free(p);
			return 1;
		}
		return 0;
	}
	Clipboard(text);
	return 0;
}

static const char *window_opts[] = { "normal", "maximized", "fullscreen", 0 };
static int
sys_window_mode(lua_State *L)
{
	int n = luaL_checkoption(L, 1, "normal", window_opts);
	WindowMode(n);
	return 0;
}

static int
sys_chdir(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	int err = chdir(path);
	lua_pushboolean(L, err == 0);
	return 1;
}

static int
sys_realpath(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	char *ret = GetRealpath(path);
	if (!ret) {
	        lua_pushstring(L, path);
		return 1;
	}
	lua_pushstring(L, ret);
	free(ret);
	return 1;
}

static int
sys_is_absolute_path(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	lua_pushboolean(L, IsAbsolutePath(path));
	return 1;
}

static int
sys_mkdir(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
#ifdef _WIN32
	int err = mkdir(path);
#else
	int err = mkdir(path, S_IRWXU);
#endif
	lua_pushboolean(L, err == 0 || errno == EEXIST);
	return 1;
}

static int
sys_time(lua_State *L)
{
	double n = Time();
	lua_pushnumber(L, n);
	return 1;
}

static int
sys_readdir(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	int lim = luaL_optnumber(L, 2, -1);
	DIR *dir = opendir(path);
	if (!dir) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_newtable(L);
	int i = 1;
	struct dirent *entry;
	while ((entry = readdir(dir))) {
		if (lim >= 0 && i > lim)
			break;
		if (strcmp(entry->d_name, "." ) == 0)
			continue;
		if (strcmp(entry->d_name, "..") == 0)
			continue;
		lua_pushstring(L, entry->d_name);
		lua_rawseti(L, -2, i);
		i++;
	}
	closedir(dir);
	return 1;
}

static int
sys_mouse(lua_State *L)
{
	int x, y;
	unsigned int mb = GetMouse(&x, &y);
	lua_pushinteger(L, x);
	lua_pushinteger(L, y);
	lua_pushinteger(L, mb);
	return 3;
}

static int
sys_input(lua_State *L)
{
	TextInput();
	return 0;
}

static int
sys_log(lua_State *L)
{
	const char *str = luaL_checkstring(L, 1);
	Log(str);
	return 0;
}

/*  Written in 2018 by David Blackman and Sebastiano Vigna (vigna@acm.org)

To the extent possible under law, the author has dedicated all copyright
and related and neighboring rights to this software to the public domain
worldwide. This software is distributed without any warranty.

See <http://creativecommons.org/publicdomain/zero/1.0/>. */

static inline unsigned int rotl(const unsigned int x, int k) {
	return (x << k) | (x >> (32 - k));
}

static unsigned int rnd_next(unsigned int *s) {
	const unsigned int result = rotl(s[1] * 5, 7) * 9;

	const unsigned int t = s[1] << 9;

	s[2] ^= s[0];
	s[3] ^= s[1];
	s[1] ^= s[2];
	s[0] ^= s[3];

	s[2] ^= t;

	s[3] = rotl(s[3], 11);

	return result;
}
/* end of xoshiro code */

static int
sys_srandom(lua_State *L)
{
	int seed;
	unsigned int *ctx;
	if (lua_isnumber(L, 1))
		seed = luaL_checknumber(L, 1);
	else
		seed = rand();
	ctx = lua_newuserdata(L, sizeof(unsigned int)*4);
	if (!ctx)
		return 0;
	memset(ctx, 0, sizeof(unsigned int)*4);
	ctx[0] = seed;
	seed ^= seed >> 12;
	ctx[1] = seed;
	seed ^= seed << 25;
	ctx[2] = seed;
	seed ^= seed >> 27;
	ctx[3] = seed;
	luaL_getmetatable(L, "mt metatable");
	lua_setmetatable(L, -2);
	return 1;
}

static int
sys_random(lua_State *L)
{
	unsigned int *ctx = (unsigned int *)luaL_checkudata(L, 1, "mt metatable");
	unsigned int r = 0;
	long a = luaL_optnumber(L, 2, -1);
	long b = luaL_optnumber(L, 3, -1);
	if (a == -1 && b == -1) {
		lua_pushnumber(L, rnd_next(ctx) * (1.0 / 4294967296.0));
		return 1;
	}
	r = rnd_next(ctx);
	if (a >= 0 && b > a)
		r = a + (r % (b - a + 1));
	else if (a > 0 && b == -1)
		r = (r % a) + 1;
	lua_pushinteger(L, r);
	return 1;
}

static int
sys_hidemouse(lua_State *L)
{
	int hide;
	if (!lua_isboolean(L, 1))
		hide = 1;
	else
		hide = lua_toboolean(L, 1);
	MouseHide(hide);
	return 0;
}

static const luaL_Reg
sys_lib[] = {
	{ "poll", sys_poll },
	{ "wait", sys_wait },
	{ "title", sys_title },
	{ "window_mode", sys_window_mode },
	{ "chdir", sys_chdir },
	{ "mkdir", sys_mkdir },
	{ "realpath", sys_realpath },
	{ "is_absolute_path", sys_is_absolute_path },
	{ "time", sys_time },
	{ "readdir", sys_readdir },
	{ "sleep", sys_sleep },
	{ "input", sys_input },
	{ "mouse", sys_mouse },
	{ "log", sys_log },
	{ "newrand", sys_srandom },
	{ "hidemouse", sys_hidemouse },
	{ "clipboard", sys_clipboard },
	{ NULL, NULL }
};

static const luaL_Reg
rand_mt[] = {
	{ "rnd", sys_random },
	{ NULL, NULL }
};

static void
mt_create_meta(lua_State *L)
{
	luaL_newmetatable(L, "mt metatable");
	luaL_setfuncs_int(L, rand_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
}

int
luaopen_system(lua_State *L)
{
	srand(time(NULL));
	mt_create_meta(L);
	luaL_newlib(L, sys_lib);
	return 1;
}

static const luaL_Reg
sys_thread_lib[] = {
	{ "time", sys_time },
	{ "sleep", sys_sleep },
	{ "newrand", sys_srandom },
	{ NULL, NULL }
};

int
luaopen_system_thread(lua_State *L)
{
	mt_create_meta(L);
	luaL_newlib(L, sys_thread_lib);
	return 1;
}
