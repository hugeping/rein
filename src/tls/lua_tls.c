/*
 * The TLS binding: tls.new(sock, host [, cert, key]) wraps a socket
 * made by net.dial into TLS 1.2, tls.certgen(name) makes a
 * self-signed client certificate.  main.c registers the whole layer
 * with one call, so it is left out by dropping that line.
 */

#include "../external.h"
#include "../net.h"
#include "../platform.h"
#include "tinytls.h"

struct lua_tls {
	ts_conn *tls;
	int fd;
};

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
tls_new(lua_State *L)
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
		size_t clen, klen;
		const char *cert = lua_tolstring(L, 3, &clen);
		const char *key = lua_tolstring(L, 4, &klen);

		if (!ts_set_clientcert(utls->tls,
			(const unsigned char *)cert, clen,
			(const unsigned char *)key, klen)) {
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
 * tls.certgen(name) -- make a self-signed P-256 certificate with the
 * common name `name`: the certificate and its PKCS#8 key, in DER.
 */
static int
tls_certgen(lua_State *L)
{
	const char *cn = luaL_optstring(L, 1, "rein");
	unsigned char cert[1024], key[128];
	size_t clen, klen;

	if (!ts_ec_selfsign(cn, cert, &clen, key, &klen)) {
		lua_pushnil(L);
		lua_pushstring(L, "can not make a certificate");
		return 2;
	}
	lua_pushlstring(L, (const char *)cert, clen);
	lua_pushlstring(L, (const char *)key, klen);
	return 2;
}

static const luaL_Reg
tls_lib[] = {
	{ "new", tls_new },
	{ "certgen", tls_certgen },
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

int
luaopen_tls(lua_State *L)
{
	luaL_newmetatable(L, "tls metatable");
	luaL_setfuncs_int(L, tls_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);
	luaL_newlib(L, tls_lib);
	return 1;
}
