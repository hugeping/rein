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

#define utf_cont(p) ((*(p) & 0xc0) == 0x80)

static int
utf_ff(const char *s, const char *e)
{
	int l = 0;
	if (!s || !e)
		return 0;
	if (s > e)
		return 0;
	if ((*s & 0x80) == 0) /* ascii */
		return 1;
	l = 1;
	while (s < e && utf_cont(s + 1)) {
		s ++;
		l ++;
	}
	return l;
}

static int
utf_bb(const char *s, const char *e)
{
	int l = 0;
	if (!s || !e)
		return 0;
	if (s > e)
		return 0;
	if ((*e & 0x80) == 0) /* ascii */
		return 1;
	l = 1;
	while (s < e && utf_cont(e)) {
		e --;
		l ++;
	}
	return l;
}

static int
sys_utf_next(lua_State *L)
{
	int l = 0;
	const char *s = luaL_optstring(L, 1, NULL);
	int idx = luaL_optnumber(L, 2, 1) - 1;
	if (s && idx >= 0) {
		int len = strlen(s);
		if (idx < len)
			l = utf_ff(s + idx, s + len - 1);
	}
#if LUA_VERSION_NUM >= 504
	lua_pushinteger(L, l);
#else
	lua_pushnumber(L, l);
#endif
	return 1;
}

static int
sys_utf_prev(lua_State *L)
{
	int l = 0;
	const char *s = luaL_optstring(L, 1, NULL);
	int idx = luaL_optnumber(L, 2, 0) - 1;
	int len = 0;
	if (s) {
		len = strlen(s);
		if (idx < 0)
			idx += len;
		if (idx >= 0) {
			if (idx < len)
				l = utf_bb(s, s + idx);
		}
	}
#if LUA_VERSION_NUM >= 504
	lua_pushinteger(L, l);
#else
	lua_pushnumber(L, l);
#endif
	return 1;
}

static int
sys_utf_sym(lua_State *L)
{
	int l = 0;
	char *rs;
	const char *s = luaL_optstring(L, 1, NULL);
	if (!s || !*s)
		return 0;
	if ((*s & 0x80)) {
		l ++;
		while (s[l] && utf_cont(s + l))
			l ++;
	} else
		l = 1;
	rs = malloc(l + 1);
	if (!rs)
		return 0;
	memcpy(rs, s, l);
	rs[l] = 0;
	lua_pushstring(L, rs);
	lua_pushnumber(L, l);
	free(rs);
	return 2;
}

static int
sys_utf_len(lua_State *L)
{
	int l = 0;
	int sym = 0;
	const char *s = luaL_optstring(L, 1, NULL);
	if (s) {
		int len = strlen(s) - 1;
		while (len >= 0) {
			l = utf_ff(s, s + len);
			if (!l)
				break;
			s += l;
			len -= l;
			sym ++;
		}
	}
	lua_pushnumber(L, sym);
	return 1;
}

static int
sys_utf_codepoint(lua_State *L)
{
	unsigned int cp = 0;
	const char *s = luaL_optstring(L, 1, NULL);
	if (s)
		utf8_to_codepoint(s, &cp);
	lua_pushnumber(L, cp);
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
	unsigned int rc, written = 0;
	float f;
#define SND_BUF_SIZE 4096
	static signed short buf[SND_BUF_SIZE];

	if (!lua_istable(L, 1)) {
		return 0;
	}
	idx = luaL_optnumber(L, 2, 1);

	len = lua_rawlen(L, 1);
	for (i = idx; i <= len; i++) {
		lua_rawgeti(L, 1, i);
		f = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		buf[pos++] = (short)((float)f * 16384.0);
		if (pos >= 4096) {
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

static const luaL_Reg
sys_lib[] = {
	{ "poll", sys_poll },
	{ "wait", sys_wait },
	{ "title", sys_title },
	{ "window_mode", sys_window_mode },
	{ "chdir", sys_chdir },
	{ "mkdir", sys_mkdir },
	{ "time", sys_time },
	{ "utf_next", sys_utf_next },
	{ "utf_prev", sys_utf_prev },
	{ "utf_len", sys_utf_len },
	{ "utf_sym", sys_utf_sym },
	{ "utf_codepoint", sys_utf_codepoint },
	{ "readdir", sys_readdir },
	{ "sleep", sys_sleep },
	{ "input", sys_input },
	{ "log", sys_log },
	{ "audio", sys_audio },
	{ "initrnd", sys_srandom },
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
system_init(lua_State *L)
{
	srand(time(NULL));
	mt_create_meta(L);
	luaL_newlib(L, sys_lib);
	return 0;
}
