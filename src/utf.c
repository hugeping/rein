#include "external.h"
#include "platform.h"

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
utf_next(lua_State *L)
{
	int l = 0;
	size_t len = 0;
	const char *s = luaL_optlstring(L, 1, NULL, &len);
	int idx = luaL_optnumber(L, 2, 1) - 1;
	if (s && idx >= 0) {
		if (idx < len)
			l = utf_ff(s + idx, s + len - 1);
	}
	lua_pushinteger(L, l);
	return 1;
}

static int
utf_chars(lua_State *L)
{
	int l, idx = 1;
	size_t len = 0;
	char sym[16];
	const char *e;
	const char *s = luaL_optlstring(L, 1, NULL, &len);
	lua_newtable(L);
	if (!s)
		return 1;
	e = s + len - 1;

	while (s <= e) {
		l = utf_ff(s, e);
		if (!l || l >= sizeof(sym))
			break;
		memcpy(sym, s, l);
		s += l;
		lua_pushlstring(L, sym, l);
		lua_rawseti(L, -2, idx ++);
	}
	return 1;
}

static int
utf_prev(lua_State *L)
{
	int l = 0;
	const char *s = luaL_optstring(L, 1, NULL);
	int idx = luaL_optnumber(L, 2, 0) - 1;
	int len;
	if (s) {
		len = strlen(s);
		if (idx < 0)
			idx += len;
		if (idx >= 0) {
			if (idx < len)
				l = utf_bb(s, s + idx);
		}
	}
	lua_pushinteger(L, l);
	return 1;
}

static int
utf_sym(lua_State *L)
{
	int l = 0;
	char rs[16];
	const char *s = luaL_optstring(L, 1, NULL);
	int off = luaL_optnumber(L, 2, 1) - 1;
	if (!s || !*s || off < 0 || off >= strlen(s))
		return 0;
	s += off;

	if ((*s & 0x80)) {
		l ++;
		while (s[l] && utf_cont(s + l))
			l ++;
	} else
		l = 1;
	if (l >= sizeof(rs))
		return 0;
	memcpy(rs, s, l);
	rs[l] = 0;
	lua_pushstring(L, rs);
	lua_pushinteger(L, l);
	return 2;
}

static int
utf_len(lua_State *L)
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

const char*
utf8_to_codepoint(const char *p, unsigned *dst)
{
	unsigned res, n;
	switch (*p & 0xf0) {
		case 0xf0 :  res = *p & 0x07;  n = 3;  break;
		case 0xe0 :  res = *p & 0x0f;  n = 2;  break;
		case 0xd0 :
		case 0xc0 :  res = *p & 0x1f;  n = 1;  break;
		default   :  res = *p;         n = 0;  break;
	}
	while (n-- && *p)
		res = (res << 6) | (*(++p) & 0x3f);
	*dst = res;
	return p + 1;
}

static int
utf_codepoint(lua_State *L)
{
	unsigned int cp = 0;
	const char *p;
	const char *s = luaL_optstring(L, 1, NULL);
	int off = luaL_optnumber(L, 2, 1) - 1;

	if (!s || off < 0 || off >= strlen(s)) {
		lua_pushinteger(L, 0);
		lua_pushinteger(L, 0);
		return 2;
	};
	p = utf8_to_codepoint(s + off, &cp);
	lua_pushinteger(L, cp);
	lua_pushinteger(L, (unsigned int)(p - (s + off)));
	return 2;
}

static const luaL_Reg
utf_lib[] = {
	{ "next", utf_next },
	{ "prev", utf_prev },
	{ "len", utf_len },
	{ "sym", utf_sym },
	{ "chars", utf_chars },
	{ "codepoint", utf_codepoint },
	{ NULL, NULL }
};

int
luaopen_utf(lua_State *L)
{
	luaL_newlib(L, utf_lib);
	return 1;
}
