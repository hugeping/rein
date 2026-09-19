#include "external.h"
#include "platform.h"
#include "tls/tinytls.h"

struct lua_sock {
	int fd;
};

struct lua_tls {
	ts_conn *tls;
	int fd;
};

static int
net_dial(lua_State *L)
{
	struct lua_sock *usock;
	int fd;
	const char *addr = luaL_checkstring(L, 1);
	const char *port = luaL_optstring(L, 2, NULL);
	char port_num[16];

	if (!port) {
		fd = luaL_checkinteger(L, 2);
		snprintf(port_num, sizeof(port_num), "%d", fd);
		port = port_num;
	}
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

/*
 * TLS transport: rein sockets are non-blocking (Send/Recv return 0
 * when the socket is not ready), which is exactly what tinytls
 * expects from its callbacks.
 */
static int
tls_read_cb(void *ctx, void *buf, size_t len)
{
	int fd = *(int *)ctx;
	int r = Recv(fd, buf, len);

	return r < 0 ? -1 : r;
}

static int
tls_write_cb(void *ctx, const void *buf, size_t len)
{
	int fd = *(int *)ctx;
	int r = Send(fd, buf, len);

	return r < 0 ? -1 : r;
}

static int
net_tls(lua_State *L)
{
	struct lua_sock *usock = luaL_checkudata(L, 1, "socket metatable");
	const char *host = luaL_optstring(L, 2, NULL);
	struct lua_tls *utls;

	utls = lua_newuserdata(L, sizeof(*utls));
	utls->fd = usock->fd;
	utls->tls = ts_new(host, &utls->fd, tls_read_cb, tls_write_cb);
	if (utls->tls == NULL) {
		lua_pushnil(L);
		lua_pushstring(L, "can not create TLS state");
		return 2;
	}
	if (lua_isstring(L, 3) && lua_isstring(L, 4)) {
		unsigned char cert[4096], key[512];
		size_t plen, clen, klen;
		const char *pem, *keypem;

		pem = lua_tolstring(L, 3, &plen);
		clen = ts_pem_decode(pem, plen, "CERTIFICATE",
			cert, sizeof cert);
		keypem = lua_tolstring(L, 4, &plen);
		klen = ts_pem_decode(keypem, plen, "PRIVATE KEY",
			key, sizeof key);
		if (klen == 0) {
			klen = ts_pem_decode(keypem, plen, "EC PRIVATE KEY",
				key, sizeof key);
		}
		if (clen == 0 || klen == 0
			|| !ts_set_clientcert(utls->tls, cert, clen, key, klen))
		{
			ts_free(utls->tls);
			utls->tls = NULL;
			utls->fd = -1;  /* the socket stays with lua_sock */
			lua_pushnil(L);
			lua_pushstring(L, "bad client certificate");
			return 2;
		}
	}
	usock->fd = -1;   /* the TLS object owns the socket from now on */
	luaL_getmetatable(L, "tls metatable");
	lua_setmetatable(L, -2);
	return 1;
}

static int
tls_handshake(lua_State *L)
{
	struct lua_tls *utls = luaL_checkudata(L, 1, "tls metatable");
	int rc = ts_handshake(utls->tls);

	if (rc == TS_OK) {
		lua_pushboolean(L, 1);
		return 1;
	}
	if (rc == TS_WANT_READ || rc == TS_WANT_WRITE) {
		lua_pushstring(L, rc == TS_WANT_READ ? "read" : "write");
		return 1;
	}
	lua_pushnil(L);
	lua_pushstring(L, ts_strerror(rc));
	return 2;
}

static int
tls_send(lua_State *L)
{
	struct lua_tls *utls = luaL_checkudata(L, 1, "tls metatable");
	int len, idx, rc;
	size_t sz;
	const char *data = luaL_checklstring(L, 2, &sz);

	idx = luaL_optinteger(L, 3, 1);
	if (lua_isnumber(L, 4))
		len = luaL_checkinteger(L, 4);
	else
		len = sz - idx + 1;

	if (idx < 1 || idx > sz)
		return luaL_error(L, "invalid send offset %d", idx);
	if (len < 0 || len > (int)sz - (idx - 1))
		return luaL_error(L, "send range exceeds string length");

	rc = ts_write(utls->tls, data + idx - 1, len);
	if (rc > 0) {
		lua_pushinteger(L, rc);
		return 1;
	}
	if (rc == TS_WANT_READ || rc == TS_WANT_WRITE) {
		lua_pushinteger(L, 0);   /* would block, like the raw socket */
		return 1;
	}
	lua_pushnil(L);
	lua_pushstring(L, ts_strerror(rc));
	return 2;
}

static int
tls_recv(lua_State *L)
{
	struct lua_tls *utls = luaL_checkudata(L, 1, "tls metatable");
	int len = luaL_checkinteger(L, 2);
	char *buf = malloc(len > 0 ? (size_t)len : 1);
	int rc;

	if (!buf) {
		lua_pushnil(L);
		lua_pushstring(L, "out of memory");
		return 2;
	}
	rc = ts_read(utls->tls, buf, (size_t)len);
	if (rc > 0) {
		lua_pushlstring(L, buf, rc);
		free(buf);
		return 1;
	}
	free(buf);
	if (rc == 0) {
		lua_pushnil(L);
		lua_pushstring(L, "closed");
		return 2;
	}
	if (rc == TS_WANT_READ || rc == TS_WANT_WRITE) {
		lua_pushliteral(L, "");   /* would block */
		return 1;
	}
	lua_pushnil(L);
	lua_pushstring(L, ts_strerror(rc));
	return 2;
}

static int
tls_close(lua_State *L)
{
	struct lua_tls *utls = luaL_checkudata(L, 1, "tls metatable");

	if (utls->tls) {
		ts_free(utls->tls);
		utls->tls = NULL;
	}
	if (utls->fd != -1) {
		Shutdown(utls->fd);
		utls->fd = -1;
	}
	return 0;
}

/*
 * net.certgen(name) -- make a self-signed P-256 certificate with the
 * common name `name`: the certificate and its PKCS#8 key, in PEM.
 */
static int
net_certgen(lua_State *L)
{
	const char *cn = luaL_optstring(L, 1, "rein");
	unsigned char cert[1024], key[128];
	char cpem[2048], kpem[512];
	size_t clen, klen, n;

	if (!ts_ec_selfsign(cn, cert, &clen, key, &klen)) {
		lua_pushnil(L);
		lua_pushstring(L, "can not make a certificate");
		return 2;
	}
	n = ts_pem_encode("CERTIFICATE", cert, clen, cpem);
	lua_pushlstring(L, cpem, n);
	n = ts_pem_encode("PRIVATE KEY", key, klen, kpem);
	lua_pushlstring(L, kpem, n);
	return 2;
}

static const luaL_Reg
net_lib[] = {
	{ "dial", net_dial },
	{ "tls", net_tls },
	{ "certgen", net_certgen },
	{ NULL, NULL }
};

static const luaL_Reg tls_mt[] = {
	{ "handshake", tls_handshake },
	{ "send", tls_send },
	{ "recv", tls_recv },
	{ "close", tls_close },
	{ "__gc", tls_close },
	{ NULL, NULL }
};

static int
sock_free(lua_State *L)
{
	struct lua_sock *usock = luaL_checkudata(L, 1, "socket metatable");
	if (usock->fd != -1)
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
	idx = luaL_optinteger(L, 3, 1);

	if (lua_isnumber(L, 4))
		len = luaL_checkinteger(L, 4);
	else
		len = sz - idx + 1;

	if (idx < 1 || idx > sz)
		return luaL_error(L, "invalid send offset %d", idx);
	if (len < 0 || len > (int)sz - (idx - 1))
		return luaL_error(L, "send range exceeds string length");

	rc = Send(usock->fd, data + idx - 1, len);
	if (rc < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lua_pushinteger(L, rc);
	return 1;
}

static int
sock_recv(lua_State *L)
{
	struct lua_sock *usock = luaL_checkudata(L, 1, "socket metatable");
	int len, rc = 0;
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
	if (rc < 0 && !written) {
		free(buf);
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		return 2;
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
	lua_pop(L, 1);
	luaL_newmetatable (L, "tls metatable");
	luaL_setfuncs_int(L, tls_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
}

int
luaopen_net(lua_State *L)
{
	sock_create_meta(L);
	luaL_newlib(L, net_lib);
	return 1;
}
