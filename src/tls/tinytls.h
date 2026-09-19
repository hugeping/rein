#ifndef TINYTLS_H
#define TINYTLS_H

#include <stddef.h>

/*
 * Tiny TLS 1.2 client: ECDHE (P-256) or static RSA key exchange,
 * AES-128-GCM records, RSA-PKCS#1 or ECDSA (P-256) certificates.
 * Certificates are parsed but never validated; a certificate with a
 * key we do not parse (ed25519, say) is accepted, its signature on
 * the key exchange is not checked.
 *
 * The engine never blocks. The transport callbacks must follow the
 * conventions of a non-blocking socket: they return the number of
 * bytes transferred, 0 when the socket is not ready (would block),
 * or a negative value on error/closure.
 *
 * Typical driver loop:
 *
 *	ts_conn *tc = ts_new("example.com", &fd, rd, wr);
 *	for (;;) {
 *		int r = ts_handshake(tc);
 *		if (r == TS_OK) break;
 *		if (r == TS_WANT_READ) wait_readable(fd);
 *		else if (r == TS_WANT_WRITE) wait_writable(fd);
 *		else fail(ts_error(tc));
 *	}
 */

typedef struct ts_conn ts_conn;

enum {
	TS_OK = 0,
	TS_WANT_READ = -1,     /* nothing to do until the socket is readable */
	TS_WANT_WRITE = -2,    /* pending output, wait for writability */
	TS_ERR_IO = -10,
	TS_ERR_PROTOCOL = -12,
	TS_ERR_UNSUPPORTED = -13,
	TS_ERR_CERTIFICATE = -14,
	TS_ERR_SIGNATURE = -15,
	TS_ERR_ALERT = -16
};

/*
 * Create a connection. server_name is sent as SNI; it may be NULL.
 * Return NULL on error.
 */
ts_conn *ts_new(const char *server_name, void *ioctx,
	int (*ioread)(void *ctx, void *buf, size_t len),
	int (*iowrite)(void *ctx, const void *buf, size_t len));

/*
 * Give the connection a client certificate (DER) and its private
 * key (DER, SEC1 or PKCS#8, P-256).  The certificate is sent only
 * if the server asks for one.  Return 0 on error.  Call it before
 * the handshake.
 */
int ts_set_clientcert(ts_conn *tc, const unsigned char *cert, size_t certlen,
	const unsigned char *key, size_t keylen);

/*
 * Make a self-signed P-256 certificate with the common name `cn`
 * and its PKCS#8 key, both in DER; cert needs 1024 bytes, key 128.
 * Return 1 on success.  The key may be fed to ts_set_clientcert,
 * the PEM functions below turn either into text.
 */
int ts_ec_selfsign(const char *cn, unsigned char *cert, size_t *certlen,
	unsigned char *key, size_t *keylen);

/*
 * PEM writer and reader for one base64 block with the given label
 * ("CERTIFICATE", "PRIVATE KEY", ...).  The output buffer of the
 * encoder must hold 4*((derlen + 2)/3) characters, the line breaks
 * and the two label lines; the decoder returns the DER length, or 0
 * when the label is not found or the data does not fit.
 */
size_t ts_pem_encode(const char *label, const unsigned char *der,
	size_t derlen, char *out);
size_t ts_pem_decode(const char *pem, size_t pemlen, const char *label,
	unsigned char *der, size_t max);

/*
 * Run the handshake. Return TS_OK when it is complete, TS_WANT_READ
 * or TS_WANT_WRITE when the caller must wait and call again, or an
 * error code (which is also remembered by ts_error()).
 */
int ts_handshake(ts_conn *tc);

/*
 * Read at most len bytes. Return the byte count, 0 on clean
 * end-of-stream (close_notify), TS_WANT_READ/TS_WANT_WRITE when the
 * caller must wait and call again, or an error code.
 */
int ts_read(ts_conn *tc, void *buf, size_t len);

/*
 * Queue up to len bytes (at most 16384) for sending. Return the
 * number of bytes accepted (0 when pending output must be flushed
 * first: wait for writability and call again), TS_WANT_READ/
 * TS_WANT_WRITE, or an error code.
 */
int ts_write(ts_conn *tc, const void *buf, size_t len);

/*
 * Push pending output. Return TS_OK, TS_WANT_WRITE or an error.
 */
int ts_flush(ts_conn *tc);

/*
 * Last error code (TS_ERR_*), or 0 if none occurred.
 */
int ts_error(ts_conn *tc);

/*
 * Human-readable description of an error code, for logs.
 */
const char *ts_strerror(int err);

/*
 * Free the connection. This never touches the transport.
 */
void ts_free(ts_conn *tc);

#endif
