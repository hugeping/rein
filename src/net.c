#include "external.h"
#include "platform.h"

struct lua_sock {
	int fd;
};

static int
net_dial(lua_State *L)
{
	struct lua_sock *usock;
	int fd;
	const char *addr = luaL_checkstring(L, 1);
	int port = luaL_checkinteger(L, 2);
	fd = Dial(addr, port);
	if (fd < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "Can not connect");
		return 2;
	}
	usock = lua_newuserdata(L, sizeof(*usock));
	usock->fd = fd;
	luaL_getmetatable(L, "socket metatable");
	lua_setmetatable(L, -2);
	return 1;
}

static const luaL_Reg
net_lib[] = {
	{ "dial", net_dial },
	{ NULL, NULL }
};

static int
sock_free(lua_State *L)
{
	struct lua_sock *usock = luaL_checkudata(L, 1, "socket metatable");
	Shutdown(usock->fd);
	usock->fd = -1;
	return 0;
}

static int
sock_send(lua_State *L)
{
	struct lua_sock *usock = luaL_checkudata(L, 1, "socket metatable");
	int len, idx, rc;
	size_t sz;
	const char *data = luaL_checklstring(L, 2, &sz);
	idx = luaL_optnumber(L, 3, 1);
	if (lua_isnumber(L, 4)) {
		len = idx + lua_tonumber(L, 3) - 1;
		if (len > sz)
			len = sz;
	} else
		len = sz;
	rc = Send(usock->fd, data + idx - 1, len);
	lua_pushinteger(L, rc);
	return 1;
}

static int
sock_recv(lua_State *L)
{
	struct lua_sock *usock = luaL_checkudata(L, 1, "socket metatable");
	int len, rc;
	int written = 0;
	char *ptr, *buf;
	len = luaL_checkinteger(L, 2);
	buf = ptr = malloc(len);
	if (!ptr)
		return 0;
	while (len) {
		rc = Recv(usock->fd, ptr, len);
		if (rc <= 0)
			break;
		ptr += rc;
		len -= rc;
		written += rc;
	}
	lua_pushlstring(L, buf, written);
	free(buf);
	return 1;
}

static const luaL_Reg socket_mt[] = {
	{ "send", sock_send },
	{ "recv", sock_recv },
	{ "close", sock_free },
	{ "__gc", sock_free },
	{ NULL, NULL }
};

void
sock_create_meta(lua_State *L)
{
	luaL_newmetatable (L, "socket metatable");
	luaL_setfuncs_int(L, socket_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
}

int
luaopen_net(lua_State *L)
{
	sock_create_meta(L);
	luaL_newlib(L, net_lib);
	return 1;
}
