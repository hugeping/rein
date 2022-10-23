#include "external.h"
#include "platform.h"
#include "gfx.h"

static int
lua_moveval(lua_State* from, int idx, lua_State* to)
{
	int type = lua_type(from, idx);
	switch(type) {
	case LUA_TNIL:
		lua_pushnil(to);
		break;
	case LUA_TBOOLEAN:
		lua_pushboolean(to, lua_toboolean(from, idx));
		break;
	case LUA_TNUMBER:
		lua_pushnumber(to, lua_tonumber(from, idx));
		break;
	case LUA_TSTRING:
		lua_pushstring(to, lua_tostring(from, idx));
		break;
	case LUA_TUSERDATA:
		if (!gfx_udata_move(from, idx, to))
			lua_pushnil(to);
		break;
	default:
		return type;
	}
	return 0;
}

static int
lua_movetable(lua_State* from, int idx, lua_State* to)
{
	int t;
	if (!lua_istable(from, idx))
		return -1;
	lua_pushvalue(from, idx);
	lua_pushnil(from);
	lua_newtable(to);
	while (lua_next(from, -2)) {
		t = lua_moveval(from, -2, to); /* key */
		if (t) {
			lua_pop(from, 1);
			continue;
		}
		t = lua_moveval(from, -1, to); /* value */

		if (!t) { /* fast path */
			lua_rawset(to, -3);
			lua_pop(from, 1);
			continue;
		}
		if (t == LUA_TTABLE) {
			lua_movetable(from, -1, to);
			lua_rawset(to, -3);
		} else
			lua_pop(to, 1); /* remove key and skip */
		lua_pop(from, 1);
	}
	lua_pop(from, 1);
	return 0;
}

struct lua_channel {
	int m; /* mutex */
	int used;
	int parent_sem;
	int child_sem;
	lua_State *parent;
	lua_State *child;
};

static void
chan_free(struct lua_channel *chan)
{
	MutexDestroy(chan->m);
	SemDestroy(chan->parent_sem);
	SemDestroy(chan->child_sem);
	free(chan);
}

struct lua_thread {
	int tid;
	lua_State *L;
	struct lua_channel *chan;
};

static int
child_read(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;

	MutexLock(chan->m);
	if (!chan->parent) {
		MutexUnlock(chan->m);
		return 0;
	}
	MutexUnlock(chan->m);
	SemPost(chan->parent_sem);
	SemWait(chan->child_sem);
	if (lua_istable(L, -1))
		return 1;
	return 0;
}

static int
child_write(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;

	MutexLock(chan->m);
	if (!chan->parent) {
		MutexUnlock(chan->m);
		return 0;
	}
	MutexUnlock(chan->m);

	SemWait(chan->child_sem);
	MutexLock(chan->m);
	if (!chan->parent) {
		MutexUnlock(chan->m);
		return 0;
	}
	if (lua_istable(L, 2))
		lua_movetable(L, 2, chan->parent);
	MutexUnlock(chan->m);

	SemPost(chan->parent_sem);
	return 0;
}

static int
child_stop(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	MutexLock(chan->m);
	chan->child = NULL;
	chan->used --;
	MutexUnlock(chan->m);
	SemPost(chan->parent_sem);
	if (!chan->used)
		chan_free(chan);
	return 0;
}

static const luaL_Reg child_thread_mt[] = {
	{ "__gc", child_stop },
	{ "read", child_read },
	{ "write", child_write },
	{ NULL, NULL }
};

static int
thread(void *data)
{
	int rc;
	struct lua_thread *thr = (struct lua_thread *)data;
	lua_callfn(thr->L);
	rc = lua_toboolean(thr->L, -1);
	lua_close(thr->L);
	return rc;
}

static int
thread_read(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;

	MutexLock(chan->m);
	if (!chan->child) {
		MutexUnlock(chan->m);
		return 0;
	}
	SemPost(chan->child_sem);
	MutexUnlock(chan->m);
	SemWait(chan->parent_sem);
	if (lua_istable(L, -1))
		return 1;
	return 0;
}

static int
thread_write(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	MutexLock(chan->m);
	if (!chan->child) {
		MutexUnlock(chan->m);
		return 0;
	}
	MutexUnlock(chan->m);

	SemWait(chan->parent_sem);
	MutexLock(chan->m);
	if (!chan->child) {
		MutexUnlock(chan->m);
		return 0;
	}
	if (lua_istable(L, 2)) {
		lua_movetable(L, 2, chan->child);
	}
	MutexUnlock(chan->m);
	SemPost(chan->child_sem);
	return 0;
}

static int
thread_new(lua_State *L)
{
	int rc = 0;
	lua_State *nL = NULL;
	struct lua_thread *thr = NULL, *child = NULL;
	struct lua_channel *chan = NULL;
	const char *code = luaL_checkstring(L, 1);
	if (!code)
		return 0;
	nL = luaL_newstate();
	if (!nL)
		return 0;
	luaL_openlibs(nL);
	pixels_create_meta(nL);

	chan = malloc(sizeof(*chan));
	if (!chan)
		goto err;

	chan->m = Mutex();
	chan->used = 2;
	chan->parent_sem = Sem(0);
	chan->child_sem = Sem(0);
	chan->parent = L;
	chan->child = nL;

	thr = lua_newuserdata(L, sizeof(struct lua_thread));
	thr->chan = chan;
	thr->tid = -1;
	thr->L = nL;

	luaL_getmetatable(L, "thread metatable");
	lua_setmetatable(L, -2);

	luaL_newmetatable (nL, "thread metatable");
	luaL_setfuncs_int(nL, child_thread_mt, 0);
	lua_pushvalue(nL, -1);
	lua_setfield(nL, -2, "__index");

	child = lua_newuserdata(nL, sizeof(struct lua_thread));
	luaL_getmetatable(nL, "thread metatable");
	lua_setmetatable(nL, -2);
	lua_setglobal(nL, "thread");

	child->tid = -1;
	child->chan = chan;

	if (luaL_loadstring(nL, code)) {
		lua_pop(L, 1); /* remove thread */
		lua_pushboolean(L, 0);
		lua_pushstring(L, lua_tostring(nL, -1));
		lua_pushstring(L, code);
		lua_remove(nL, -2); /* remove thread */
		rc = 3;
		goto err2;
	}

	thr->tid = Thread(thread, thr);

	return 1;
err:
	if (chan) {
		MutexDestroy(chan->m);
		SemDestroy(chan->parent_sem);
		SemDestroy(chan->child_sem);
		free(chan);
	}
	if (child)
		free(child);
	if (thr)
		free(thr);
err2:
	if (nL)
		lua_close(nL);
	return rc;
}

static int
thread_wait(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	int status = ThreadWait(thr->tid);
	chan->child = NULL;
	chan->used = 0;
	chan_free(chan);
	thr->chan = NULL;
	lua_pushboolean(L, status);
	return 1;
}

static int
thread_stop(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	int haschild;
	if (!chan)
		return 0;
	MutexLock(chan->m);
	chan->parent = NULL;
	haschild = !!chan->child;
	MutexUnlock(chan->m);
	if (haschild) {
		SemPost(chan->child_sem);
		thread_wait(L);
	}
	return 0;
}

static const luaL_Reg thread_mt[] = {
	{ "wait", thread_wait },
	{ "write", thread_write },
	{ "read", thread_read },
	{ "__gc", thread_stop },
	{ NULL, NULL }
};

static const luaL_Reg
thread_lib[] = {
	{ "new", thread_new },
	{ NULL, NULL }
};

int
thread_init(lua_State *L)
{
	luaL_newmetatable (L, "thread metatable");
	luaL_setfuncs_int(L, thread_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	luaL_newlib(L, thread_lib);
	return 0;
}
