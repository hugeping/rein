#include "external.h"
#include "platform.h"
#include "gfx.h"
#include "tinymt32.h"

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

static int
sys_audio(lua_State *L)
{
	int len, i, idx;
	int pos = 0;
	int channels = 1;
	short sample;
	unsigned int rc, written = 0;
	float f;
#define SND_BUF_SIZE 4096
	static signed short buf[SND_BUF_SIZE];
	if (!lua_istable(L, 1))
		return 0;

	lua_getfield(L, 1, "channels");
	channels = luaL_optinteger(L, -1, 1);
	lua_pop(L, 1);

	if (channels > 2 || channels < 1)
		return 0;

	idx = luaL_optnumber(L, 2, 1);
	if (lua_isnumber(L, 3)) {
		len = idx + lua_tonumber(L, 3) - 1;
		if (len > lua_rawlen(L, 1))
			len = lua_rawlen(L, 1);
	} else
		len = lua_rawlen(L, 1);
	for (i = idx; i <= len; i++) {
		lua_rawgeti(L, 1, i);
		f = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		sample = (short)((float)f * 16384.0);
		buf[pos++] = sample;
		if (channels == 1)
			buf[pos++] = sample;
		if (pos >= SND_BUF_SIZE) {
			rc = AudioWrite(buf, pos * 2);
			written += rc;
			pos = 0;
			if (rc < SND_BUF_SIZE)
				break;
		}
	}
	if (pos > 0) {
		rc = AudioWrite(buf, pos * 2);
		written += rc;
	}
	if (channels == 1)
		written /= 2;
	lua_pushinteger(L, written / 2);
	return 1;
#undef SND_BUF_SIZE
}

static int
sys_srandom(lua_State *L)
{
	int seed;
	tinymt32_t *mt;
	if (lua_isnumber(L, 1))
		seed = luaL_checknumber(L, 1);
	else
		seed = rand();
	mt = lua_newuserdata(L, sizeof(tinymt32_t));
	if (!mt)
		return 0;
	memset(mt, 0, sizeof(*mt));
	tinymt32_init(mt, seed);
	luaL_getmetatable(L, "mt metatable");
	lua_setmetatable(L, -2);
	return 1;
}

static int
sys_random(lua_State *L)
{
	tinymt32_t *mt = (tinymt32_t *)luaL_checkudata(L, 1, "mt metatable");
	unsigned int r = 0;
	long a = luaL_optnumber(L, 2, -1);
	long b = luaL_optnumber(L, 3, -1);
	if (a == -1 && b == -1) {
		lua_pushnumber(L, tinymt32_generate_32double(mt));
		return 1;
	}
	r = tinymt32_generate_uint32(mt);
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
	{ "time", sys_time },
	{ "readdir", sys_readdir },
	{ "sleep", sys_sleep },
	{ "input", sys_input },
	{ "log", sys_log },
	{ "audio", sys_audio },
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
	{ "audio", sys_audio },
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
