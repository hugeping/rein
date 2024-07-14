#include "external.h"
#ifndef LUA_BITLIBNAME_OWN
/*
* Stripped down code from the Lua BitOp library (MIT)
** Original code: http://bitop.luajit.org/
**
** Copyright (C) 2008-2012 Mike Pall. All rights reserved.
**
** [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
** 
*/

#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"

#ifdef _MSC_VER
typedef __int32 int32_t;
typedef unsigned __int32 uint32_t;
#else
#include <stdint.h>
#endif

static inline uint32_t barg(lua_State *L, int idx)
{
	return ((uint32_t)luaL_checknumber(L, idx)) & 0xffffffff;
}

/* Return bit type. */
#define BRET(b)  lua_pushnumber(L, ((uint32_t)b & 0xffffffff)); return 1;

static int bit_tobit(lua_State *L) { BRET(barg(L, 1)) }
static int bit_bnot(lua_State *L) { BRET(~barg(L, 1)) }

#define BIT_OP(func, opr) \
  static int func(lua_State *L) { int i; uint32_t b = barg(L, 1); \
    for (i = lua_gettop(L); i > 1; i--) b opr barg(L, i); \
    BRET(b) }
BIT_OP(bit_band, &=)
BIT_OP(bit_bor, |=)
BIT_OP(bit_bxor, ^=)

#define bshl(b, n)  (b << n)
#define bshr(b, n)  (b >> n)
#define bsar(b, n)  ((int32_t)b >> n)
#define brol(b, n)  ((b << n) | (b >> (32-n)))
#define bror(b, n)  ((b << (32-n)) | (b >> n))
#define BIT_SH(func, fn) \
  static int func(lua_State *L) { \
    uint32_t b = barg(L, 1); uint32_t n = barg(L, 2) & 31; BRET(fn(b, n)) }
BIT_SH(bit_lshift, bshl)
BIT_SH(bit_rshift, bshr)
BIT_SH(bit_arshift, bsar)
BIT_SH(bit_rol, brol)
BIT_SH(bit_ror, bror)

static int bit_bswap(lua_State *L)
{
	uint32_t b = barg(L, 1);
	b = (b >> 24) | ((b >> 8) & 0xff00) | ((b & 0xff00) << 8) | (b << 24);
	BRET(b)
}

static int bit_tohex(lua_State *L)
{
	uint32_t b = barg(L, 1);
	int32_t n = lua_isnone(L, 2) ? 8 : (int32_t)barg(L, 2);
	const char *hexdigits = "0123456789abcdef";
	char buf[8];
	int i;
	if (n < 0) { n = -n; hexdigits = "0123456789ABCDEF"; }
	if (n > 8) n = 8;
	for (i = (int)n; --i >= 0; ) { buf[i] = hexdigits[b & 15]; b >>= 4; }
	lua_pushlstring(L, buf, (size_t)n);
	return 1;
}

static const struct luaL_Reg bit_funcs[] = {
	{ "tobit",	bit_tobit },
	{ "bnot",	bit_bnot },
	{ "band",	bit_band },
	{ "bor",	bit_bor },
	{ "bxor",	bit_bxor },
	{ "lshift",	bit_lshift },
	{ "rshift",	bit_rshift },
	{ "arshift",	bit_arshift },
	{ "rol",	bit_rol },
	{ "ror",	bit_ror },
	{ "bswap",	bit_bswap },
	{ "tohex",	bit_tohex },
	{ NULL, NULL }
};

#define BAD_SAR		(bsar(-8, 2) != (SBits)-2)

LUALIB_API int luaopen_bit(lua_State *L)
{
	luaL_newlib(L, bit_funcs);
	return 1;
}
#endif
