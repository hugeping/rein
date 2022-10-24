#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#if !defined LUA_VERSION_NUM || LUA_VERSION_NUM==501
void
luaL_setfuncs_int(lua_State *L, const luaL_Reg *l, int nup)
{
	luaL_checkstack(L, nup+1, "too many upvalues");
	for (; l->name != NULL; l++) {  /* fill the table with given functions */
		int i;
		lua_pushstring(L, l->name);
		for (i = 0; i < nup; i++)  /* copy upvalues to the top */
			lua_pushvalue(L, -(nup+1));
		lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
		lua_settable(L, -(nup + 3));
	}
	lua_pop(L, nup);  /* remove upvalues */
}
void
luaL_requiref(lua_State *L, char const* modname,
                    lua_CFunction openf, int glb)
{
	luaL_checkstack(L, 3, "not enough stack slots");
	lua_pushcfunction(L, openf);
	lua_pushstring(L, modname);
	lua_call(L, 1, 1);
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "loaded");
	lua_replace(L, -2);
	lua_pushvalue(L, -2);
	lua_setfield(L, -2, modname);
	lua_pop(L, 1);
	if (glb) {
		lua_pushvalue(L, -1);
		lua_setglobal(L, modname);
	}
}
int
lua_rawlen(lua_State *L, int idx)
{
	return lua_objlen(L, idx);
}
#else
void
luaL_setfuncs_int(lua_State *L, const luaL_Reg *l, int nup)
{
	luaL_setfuncs(L, l, nup);
}
#endif

static int
report(lua_State *L, int status)
{
	const char *msg;
	if (!status || lua_isnil(L, -1))
		return 0;
	msg = lua_tostring(L, -1);
	if (msg)
		fprintf(stderr,"%s\n", msg);
//	lua_pop(L, 1);
	return status;
}

static int
traceback(lua_State *L)
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

int
lua_callfn(lua_State *L)
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
