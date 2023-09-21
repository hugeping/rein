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

struct lua_peer {
	int sem;
	int write;
	int read;
	int poll;
	lua_State *L;
};

struct lua_channel {
	int m; /* mutex */
	int used;
	struct lua_peer peers[2];
};

static void
chan_free(struct lua_channel *chan)
{
	MutexDestroy(chan->m);
	SemDestroy(chan->peers[0].sem);
	SemDestroy(chan->peers[1].sem);
	free(chan);
}

struct lua_thread {
	int tid;
	lua_State *L;
	char *err;
	struct lua_channel *chan;
};

static int
thread_poll(lua_State *L)
{
	int ms = -1, rc;
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	float to = luaL_optnumber(L, 2, 0);
	struct lua_channel *chan = thr->chan;
	struct lua_peer *other = (thr->tid >= 0)?&chan->peers[1]:&chan->peers[0];
	struct lua_peer *self = (thr->tid >= 0)?&chan->peers[0]:&chan->peers[1];
	if (to != -1)
		ms = to * 1000; /* seconds to ms */

	MutexLock(chan->m);
	if (thr->err) {
		MutexUnlock(chan->m);
		return luaL_error(L, thr->err);
	}
	if (!other->L) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread poll");
	}
	if (other->write || other->read) {
		lua_pushboolean(L, !!other->write);
		lua_pushboolean(L, !!other->read);
		MutexUnlock(chan->m);
		return 2;
	}
	self->poll ++;
	MutexUnlock(chan->m);
	rc = SemWait(self->sem, ms);
	MutexLock(chan->m);
	if (rc && !self->poll) {
		SemWait(self->sem, 0);
	}
	if (self->poll)
		self->poll --;
	lua_pushboolean(L, !!other->write);
	lua_pushboolean(L, !!other->read);
	MutexUnlock(chan->m);
	return 2;
}

static int
thread_read(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	struct lua_peer *other = (thr->tid >= 0)?&chan->peers[1]:&chan->peers[0];
	struct lua_peer *self = (thr->tid >= 0)?&chan->peers[0]:&chan->peers[1];
	MutexLock(chan->m);
	if (thr->err) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread read: %s", thr->err);
	}
	if (other->read) {
		MutexUnlock(chan->m);
		return luaL_error(L, "Deadlock thread on read");
	}
	if (!other->L) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread read");
	}
	self->read ++;
	if (self->L != L) /* coroutines? */
		self->L = L;
	if (other->poll) {
		SemPost(other->sem);
		other->poll --;
	}
	MutexUnlock(chan->m);
	SemPost(other->sem);
	SemWait(self->sem, -1);
	return lua_gettop(L) - 1;
}

static int
thread_write(lua_State *L)
{
	int i, top;
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	struct lua_peer *other = (thr->tid >= 0)?&chan->peers[1]:&chan->peers[0];
	struct lua_peer *self = (thr->tid >= 0)?&chan->peers[0]:&chan->peers[1];

	MutexLock(chan->m);

	if (thr->err) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread write: %s", thr->err);
	}

	if (!other->L) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread write");
	}

	if (other->write) {
		MutexUnlock(chan->m);
		return luaL_error(L, "Deadlock on thread write: both writing");
	}

	self->write ++;
	if (self->L != L) /* coroutines? */
		self->L = L;
	if (other->poll) {
		SemPost(other->sem);
		other->poll --;
	}
	MutexUnlock(chan->m);
	SemWait(self->sem, -1);
	MutexLock(chan->m);
	self->write --;
	if (thr->err) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread write: %s", thr->err);
	}
	if (!other->L) {
		MutexUnlock(chan->m);
		return luaL_error(L, "No peer on thread write");
	}
	top = lua_gettop(L);
	for (i = 2; i <= top; i++) {
		if (lua_istable(L, i))
			lua_movetable(L, i, other->L);
		else
			lua_moveval(L, i, other->L);
	}
	other->read --;
	MutexUnlock(chan->m);
	SemPost(other->sem);
	lua_pushboolean(L, 1);
	return 1;
}

static int
child_stop(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	MutexLock(chan->m);
	chan->peers[1].L = NULL;
	chan->used --;
	MutexUnlock(chan->m);
	SemPost(chan->peers[0].sem);
	if (!chan->used)
		chan_free(chan);
	return 0;
}

static const luaL_Reg child_thread_mt[] = {
	{ "__gc", child_stop },
	{ "read", thread_read },
	{ "poll", thread_poll },
	{ "write", thread_write },
	{ NULL, NULL }
};

static int
thread(void *data)
{
	int rc;
	struct lua_thread *thr = (struct lua_thread *)data;
	if (lua_callfn(thr->L)) {
		if (thr->chan) {
			MutexLock(thr->chan->m);
			if (!thr->err)
				thr->err = strdup(lua_tostring(thr->L, -1));
			MutexUnlock(thr->chan->m);
		}
		lua_pop(thr->L, 1);
	}
	rc = lua_toboolean(thr->L, -1);
	lua_close(thr->L);
	return rc;
}

static int
thread_err(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	const char *err = luaL_optstring(L, 2, NULL);
	struct lua_channel *chan = thr->chan;
	struct lua_peer *other = (thr->tid >= 0)?&chan->peers[1]:&chan->peers[0];

	MutexLock(chan->m);
	if (err) {
		thr->err = strdup(err);
		MutexUnlock(chan->m);
		return 0;
	}
	if (thr->err) {
		lua_pushstring(L, thr->err);
		MutexUnlock(chan->m);
		return 1;
	}
	if (!other->L) {
		MutexUnlock(chan->m);
		lua_pushstring(L, "No peer");
		return 1;
	}
	MutexUnlock(chan->m);
	return 0;
}

extern int luaopen_system_thread(lua_State *L);
extern int luaopen_bit(lua_State *L);
extern int luaopen_utf(lua_State *L);
extern int luaopen_net(lua_State *L);
extern int luaopen_synth(lua_State *L);

static const luaL_Reg lua_libs[] = {
	{ "sys",  luaopen_system_thread },
	{ "bit", luaopen_bit },
	{ "utf", luaopen_utf },
	{ "net", luaopen_net },
	{ "synth", luaopen_synth },
	{ NULL, NULL }
};

static int
lua_thread_init(lua_State *L)
{
	int i;
	for (i = 0; lua_libs[i].name; i++)
		luaL_requiref(L, lua_libs[i].name, lua_libs[i].func, 1);
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
	int file = lua_toboolean(L, 2);
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
	memset(chan, 0, sizeof(*chan));
	chan->m = Mutex();
	chan->used = 2;

	chan->peers[0].sem = Sem(0);
	chan->peers[0].L = L;
	chan->peers[1].sem = Sem(0);
	chan->peers[1].L = nL;

	thr = lua_newuserdata(L, sizeof(struct lua_thread));
	thr->chan = chan;
	thr->tid = -1;
	thr->L = nL;
	thr->err = NULL;

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

	lua_pushboolean(nL, 1);
	lua_setglobal(nL, "THREAD");

	lua_thread_init(nL);

	lua_getglobal(L, "EXEFILE");
	lua_pushstring(nL, lua_tostring(L, -1));
	lua_pop(L, 1);
	lua_setglobal(nL, "EXEFILE");

	lua_getglobal(L, "DATADIR");
	lua_pushstring(nL, lua_tostring(L, -1));
	lua_pop(L, 1);
	lua_setglobal(nL, "DATADIR");

	child->tid = -1;
	child->chan = chan;
	child->err = NULL;

	if (file)
		rc = luaL_loadfile(nL, code);
	else
		rc = luaL_loadstring(nL, code);
	if (rc) {
		lua_pop(L, 1); /* remove thread */
		lua_pushboolean(L, 0);
		lua_pushstring(L, lua_tostring(nL, -1));
		lua_pushstring(L, code);
		lua_remove(nL, -2); /* remove thread */
		rc = 3;
		goto err2;
	}
	lua_getglobal(L, "package");
	if (lua_istable(L, -1)) {
		lua_getfield(L, -1, "path");
		lua_getglobal(nL, "package");
		lua_pushstring(nL, lua_tostring(L, -1));
		lua_pop(L, 2);
		lua_setfield(nL, -2, "path");
	}
	lua_pop(nL, 1);
	thr->tid = Thread(thread, thr);

	return 1;
err:
	if (chan) {
		MutexDestroy(chan->m);
		SemDestroy(chan->peers[0].sem);
		SemDestroy(chan->peers[1].sem);
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
	chan->peers[1].L = NULL;
	chan->used = 0;
//	chan_free(chan);
//	thr->chan = NULL;
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
//	printf("Thread stop\n");
	MutexLock(chan->m);
	chan->peers[0].L = NULL;
	haschild = !!chan->peers[1].L;
	MutexUnlock(chan->m);
	if (haschild) {
		SemPost(chan->peers[1].sem);
		thread_wait(L);
	}
	chan_free(chan);
	thr->chan = NULL;
	if (thr->err)
		free(thr->err);
	return 0;
}

static int
thread_detach(lua_State *L)
{
	struct lua_thread *thr = (struct lua_thread*)luaL_checkudata(L, 1, "thread metatable");
	struct lua_channel *chan = thr->chan;
	int haschild;
	if (!chan)
		return 0;
	MutexLock(chan->m);
	chan->peers[0].L = NULL;
	haschild = !!chan->peers[1].L;
	if (haschild) {
		SemPost(chan->peers[1].sem);
		chan->peers[1].L = NULL;
		chan->used = 1;
	} else {
		MutexUnlock(chan->m);
		chan_free(chan);
		chan = NULL;
	}
	thr->chan = NULL;

	if (thr->err)
		free(thr->err);
	thr->err = NULL;
	if (chan)
		MutexUnlock(chan->m);
	return 0;
}

static const luaL_Reg thread_mt[] = {
	{ "wait", thread_wait },
	{ "write", thread_write },
	{ "read", thread_read },
	{ "poll", thread_poll },
	{ "err", thread_err },
	{ "detach", thread_detach },
	{ "__gc", thread_stop },
	{ NULL, NULL }
};

static const luaL_Reg
thread_lib[] = {
	{ "new", thread_new },
	{ NULL, NULL }
};

int
luaopen_thread(lua_State *L)
{
#ifndef __EMSCRIPTEN__
	luaL_newmetatable (L, "thread metatable");
	luaL_setfuncs_int(L, thread_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	luaL_newlib(L, thread_lib);
	return 1;
#else
	return 0;
#endif
}
