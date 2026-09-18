#ifndef TS_PRIV_H
#define TS_PRIV_H

#include <stddef.h>
#include <stdint.h>

#include "bearssl_ec.h"
#include "bearssl_rsa.h"

/*
 * ts_crypto.c (SHA-256, AES-128/CTR, GHASH, HMAC/PRF, RNG) is our
 * own, as is all the TLS code. What remains from BearSSL (see
 * LICENSE.txt and the files with br_ names) is the big-integer and
 * curve arithmetic, and the RSA/ECDSA signature checks.
 */

#define TS_MAXRSA     512   /* 4096-bit modulus */
#define TS_MAXPLAIN   16384
#define TS_MAXCIPHER  (TS_MAXPLAIN + 2048)
#define TS_MAXHAND    (TS_MAXPLAIN * 2)

typedef struct {
	uint32_t val[8];
	unsigned char buf[64];
	uint64_t count;
} ts_sha256_ctx;

void ts_sha256_init(ts_sha256_ctx *ctx);
void ts_sha256_update(ts_sha256_ctx *ctx, const void *data, size_t len);
void ts_sha256_out(const ts_sha256_ctx *ctx, void *out);

typedef struct {
	unsigned char rk[176];
} ts_aes_ctx;

void ts_aes_init(ts_aes_ctx *ctx, const void *key);
void ts_aes_ctr_xor(const ts_aes_ctx *ctx, const unsigned char iv[12],
	uint32_t cc, void *data, size_t len);

void ts_ghash(void *y, const void *h, const void *data, size_t len);

#define TS_KEY_NONE  0
#define TS_KEY_RSA   1
#define TS_KEY_EC    2

typedef struct {
	int key_type;
	union {
		br_rsa_public_key rsa;
		br_ec_public_key ec;
	} key;
} ts_pkey;

struct ts_conn {
	void *ioctx;
	int (*ioread)(void *ctx, void *buf, size_t len);
	int (*iowrite)(void *ctx, const void *buf, size_t len);
	int err;

	char sni[256];

	unsigned char client_random[32];
	unsigned char server_random[32];
	unsigned char master[48];

	unsigned char wkey[16], wiv[4];
	unsigned char rkey[16], riv[4];
	unsigned char wh[16], rh[16];
	ts_aes_ctx waes, raes;
	uint64_t seq_out, seq_in;
	int enc_out, enc_in;

	ts_sha256_ctx hs;
	ts_pkey pkey;

	/* inbound: raw record being assembled (header included) */
	unsigned char rbuf[5 + TS_MAXCIPHER];
	size_t in_have, in_need;
	unsigned rtype;
	size_t rlen;

	/* outbound: pending record (NULL when empty) */
	unsigned char wbuf[5 + TS_MAXCIPHER];
	size_t wlen, wpos;

	unsigned char hbuf[TS_MAXHAND];
	size_t hlen;

	unsigned char cert[8192];
	unsigned char pms[512];
	size_t pms_len;
	unsigned char exch[TS_MAXRSA + 2];
	size_t exch_len;

	int hs_state;
	unsigned suite;
	int seen_cr;

	unsigned char app[TS_MAXPLAIN];
	size_t app_len, app_pos;
	int eof;
};
/* ts_prf.c */
void ts_random(void *buf, size_t len);
void ts_prf(const void *secret, size_t slen, const char *label,
	const void *seed, size_t seed_len, void *out, size_t out_len);

/* ts_x509.c */
int ts_x509_get_pkey(const unsigned char *cert, size_t clen, ts_pkey *pk);

#endif
