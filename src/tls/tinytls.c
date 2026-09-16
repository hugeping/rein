/*
 * Tiny TLS 1.2 client.
 *
 * Supported: TLS 1.2 only; cipher suites ECDHE_RSA/ECDHE_ECDSA
 * AES-128-GCM and static RSA AES-128-GCM; P-256; SHA-256;
 * RSA-PKCS#1 and ECDSA signatures on the ServerKeyExchange;
 * RSA and P-256 ECDSA server certificates (parsed, never
 * validated).
 *
 * The engine is non-blocking: the transport callbacks return 0
 * when the socket is not ready, and ts_handshake()/ts_read()/
 * ts_write() return TS_WANT_READ/TS_WANT_WRITE so that the caller
 * can wait and retry (see tinytls.h).
 *
 * The primitives (SHA-256, AES, GHASH, PRF, RNG) live in
 * ts_crypto.c; the big-integer/curve/RSA/ECDSA math comes from a
 * trimmed BearSSL copy (the files named after br_ functions).
 */

#include <stdlib.h>
#include <string.h>

#include "tinytls.h"
#include "ts_priv.h"

/* ---- byte accessors ---- */

static void
put16(unsigned char *p, unsigned v)
{
	p[0] = (unsigned char)(v >> 8);
	p[1] = (unsigned char)v;
}

static unsigned
get16(const unsigned char *p)
{
	return ((unsigned)p[0] << 8) | (unsigned)p[1];
}

static void
put24(unsigned char *p, size_t v)
{
	p[0] = (unsigned char)(v >> 16);
	p[1] = (unsigned char)(v >> 8);
	p[2] = (unsigned char)v;
}

static size_t
get24(const unsigned char *p)
{
	return ((size_t)p[0] << 16) | ((size_t)p[1] << 8) | (size_t)p[2];
}

static void
put64(unsigned char *p, uint64_t v)
{
	int i;

	for (i = 7; i >= 0; i --) {
		p[i] = (unsigned char)v;
		v >>= 8;
	}
}

/* ---- GCM (AES-128 only) ---- */

static void
gcm_ghash(unsigned char y[16], const unsigned char h[16],
	const void *data, size_t len)
{
	if (len > 0) {
		ts_ghash(y, h, data, len);
	}
}

static void
gcm_h(const ts_aes_ctx *aes, unsigned char h[16])
{
	unsigned char z[12];

	/*
	 * ts_aes_ctr_xor() XORs the keystream into the provided
	 * buffer, so it must be zeroed first (both here and for the
	 * tag mask below).
	 */
	memset(z, 0, sizeof z);
	memset(h, 0, 16);
	ts_aes_ctr_xor(aes, z, 0, h, 16);
}

static void
gcm_mask(const ts_aes_ctx *aes, const unsigned char nonce[12],
	unsigned char m[16])
{
	memset(m, 0, 16);
	ts_aes_ctr_xor(aes, nonce, 1, m, 16);
}

static void
gcm_tag(const ts_aes_ctx *aes, const unsigned char h[16],
	const unsigned char nonce[12], const unsigned char *aad,
	size_t aad_len, const unsigned char *ct, size_t ct_len,
	unsigned char tag[16])
{
	unsigned char y[16], lenblk[16], mask[16];
	size_t u;

	memset(y, 0, sizeof y);
	gcm_ghash(y, h, aad, aad_len);
	gcm_ghash(y, h, ct, ct_len);
	put64(lenblk, (uint64_t)aad_len * 8);
	put64(lenblk + 8, (uint64_t)ct_len * 8);
	gcm_ghash(y, h, lenblk, sizeof lenblk);
	gcm_mask(aes, nonce, mask);
	for (u = 0; u < 16; u ++) {
		tag[u] = y[u] ^ mask[u];
	}
}

/* ---- records ---- */

/* ---- records ---- */

static void
rec_aad(unsigned char aad[13], uint64_t seq, unsigned type, size_t len)
{
	put64(aad, seq);
	aad[8] = (unsigned char)type;
	aad[9] = 0x03;
	aad[10] = 0x03;
	put16(aad + 11, (unsigned)len);
}

static int
rec_flush(ts_conn *t)
{
	while (t->wpos < t->wlen) {
		int r = t->iowrite(t->ioctx, t->wbuf + t->wpos,
			t->wlen - t->wpos);

		if (r < 0) {
			t->err = TS_ERR_IO;
			return TS_ERR_IO;
		}
		if (r == 0) {
			return TS_WANT_WRITE;
		}
		t->wpos += (size_t)r;
	}
	t->wpos = 0;
	t->wlen = 0;
	return TS_OK;
}

static int
rec_queue(ts_conn *t, unsigned type, const void *data, size_t len)
{
	unsigned char *p = t->wbuf;

	if (t->wlen != 0 || len > TS_MAXPLAIN) {
		t->err = TS_ERR_PROTOCOL;
		return TS_ERR_PROTOCOL;
	}
	p[0] = (unsigned char)type;
	p[1] = 0x03;
	p[2] = 0x03;
	if (t->enc_out) {
		unsigned char aad[13], nonce[12];

		put64(p + 5, t->seq_out);
		memcpy(p + 13, data, len);
		memcpy(nonce, t->wiv, 4);
		memcpy(nonce + 4, p + 5, 8);
		ts_aes_ctr_xor(&t->waes, nonce, 2, p + 13, len);
		rec_aad(aad, t->seq_out, type, len);
		gcm_tag(&t->waes, t->wh, nonce, aad, sizeof aad,
			p + 13, len, p + 13 + len);
		t->wlen = 5 + 8 + len + 16;
	} else {
		memcpy(p + 5, data, len);
		t->wlen = 5 + len;
	}
	put16(p + 3, (unsigned)(t->wlen - 5));
	t->seq_out ++;
	t->wpos = 0;
	return TS_OK;
}

static int
rec_pull(ts_conn *t)
{
	while (t->in_need == 0 || t->in_have < t->in_need) {
		size_t want = t->in_need == 0 ? 5 : t->in_need;
		int r = t->ioread(t->ioctx, t->rbuf + t->in_have,
			want - t->in_have);

		if (r < 0) {
			t->err = TS_ERR_IO;
			return TS_ERR_IO;
		}
		if (r == 0) {
			return TS_WANT_READ;
		}
		t->in_have += (size_t)r;
		if (t->in_need == 0 && t->in_have == 5) {
			size_t len = get16(t->rbuf + 3);

			if (len > TS_MAXCIPHER) {
				t->err = TS_ERR_PROTOCOL;
				return TS_ERR_PROTOCOL;
			}
			t->in_need = 5 + len;
		}
	}
	return TS_OK;
}

static int
rec_next(ts_conn *t)
{
	int r = rec_pull(t);
	size_t rlen;
	unsigned type;

	if (r != TS_OK) {
		return r;
	}
	type = t->rbuf[0];
	rlen = t->in_need - 5;
	if (t->enc_in) {
		unsigned char aad[13], nonce[12], tag[16];
		size_t clen;

		if (rlen < 8 + 16) {
			t->err = TS_ERR_PROTOCOL;
			return TS_ERR_PROTOCOL;
		}
		clen = rlen - 8 - 16;
		memcpy(nonce, t->riv, 4);
		memcpy(nonce + 4, t->rbuf + 5, 8);
		rec_aad(aad, t->seq_in, type, clen);
		gcm_tag(&t->raes, t->rh, nonce, aad, sizeof aad,
			t->rbuf + 13, clen, tag);
		if (memcmp(tag, t->rbuf + 13 + clen, 16) != 0) {
			t->err = TS_ERR_PROTOCOL;
			return TS_ERR_PROTOCOL;
		}
		ts_aes_ctr_xor(&t->raes, nonce, 2, t->rbuf + 13, clen);
		memmove(t->rbuf, t->rbuf + 13, clen);
		rlen = clen;
	} else {
		memmove(t->rbuf, t->rbuf + 5, rlen);
	}
	t->seq_in ++;
	t->rtype = type;
	t->rlen = rlen;
	t->in_have = 0;
	t->in_need = 0;
	return TS_OK;
}

/* ---- handshake messages ---- */

static int
hs_send(ts_conn *t, unsigned type, const void *body, size_t len)
{
	unsigned char b[2048];

	if (t->wlen != 0) {
		return TS_WANT_WRITE;
	}
	if (len + 4 > sizeof b) {
		t->err = TS_ERR_PROTOCOL;
		return TS_ERR_PROTOCOL;
	}
	b[0] = (unsigned char)type;
	put24(b + 1, len);
	if (len > 0) {
		memcpy(b + 4, body, len);
	}
	ts_sha256_update(&t->hs, b, len + 4);
	return rec_queue(t, 22, b, len + 4);
}

static int
hs_next(ts_conn *t, unsigned *type, const unsigned char **body, size_t *len)
{
	for (;;) {
		if (t->hlen >= 4) {
			size_t blen = get24(t->hbuf + 1);

			if (blen > sizeof t->hbuf - 4) {
				t->err = TS_ERR_PROTOCOL;
				return TS_ERR_PROTOCOL;
			}
			if (t->hlen >= 4 + blen) {
				*type = t->hbuf[0];
				*body = t->hbuf + 4;
				*len = blen;
				ts_sha256_update(&t->hs, t->hbuf, 4 + blen);
				return TS_OK;
			}
		}
		if (t->hlen >= sizeof t->hbuf) {
			t->err = TS_ERR_PROTOCOL;
			return TS_ERR_PROTOCOL;
		}
		{
			int r = rec_next(t);

			if (r != TS_OK) {
				return r;
			}
			if (t->rtype == 22) {
				if (t->rlen > sizeof t->hbuf - t->hlen) {
					t->err = TS_ERR_PROTOCOL;
					return TS_ERR_PROTOCOL;
				}
				memcpy(t->hbuf + t->hlen, t->rbuf, t->rlen);
				t->hlen += t->rlen;
				continue;
			}
			t->err = t->rtype == 21 ? TS_ERR_ALERT
				: TS_ERR_PROTOCOL;
			return t->err;
		}
	}
}

static void
hs_skip(ts_conn *t, size_t n)
{
	memmove(t->hbuf, t->hbuf + n, t->hlen - n);
	t->hlen -= n;
}

/* ---- ClientHello ---- */

static int
send_clienthello(ts_conn *t)
{
	unsigned char b[1024], ext[512];
	size_t n, e, hlen;

	hlen = strlen(t->sni);
	n = 0;
	b[n ++] = 0x03;
	b[n ++] = 0x03;
	memcpy(b + n, t->client_random, 32);
	n += 32;
	b[n ++] = 0;                       /* session ID: empty */
	put16(b + n, 6);                   /* cipher suites */
	n += 2;
	put16(b + n, 0xC02B);              /* ECDHE_ECDSA_AES128_GCM */
	n += 2;
	put16(b + n, 0xC02F);              /* ECDHE_RSA_AES128_GCM */
	n += 2;
	put16(b + n, 0x009C);              /* RSA_AES128_GCM */
	n += 2;
	b[n ++] = 1;                       /* compression: null */
	b[n ++] = 0;

	e = 0;
	if (hlen > 0) {
		ext[e ++] = 0x00;              /* SNI */
		ext[e ++] = 0x00;
		put16(ext + e, hlen + 5);
		e += 2;
		put16(ext + e, hlen + 3);
		e += 2;
		ext[e ++] = 0;                 /* host_name */
		put16(ext + e, hlen);
		e += 2;
		memcpy(ext + e, t->sni, hlen);
		e += hlen;
	}
	ext[e ++] = 0x00;                  /* signature_algorithms */
	ext[e ++] = 0x0D;
	put16(ext + e, 6);
	e += 2;
	put16(ext + e, 4);
	e += 2;
	ext[e ++] = 0x04;                  /* ecdsa_secp256r1_sha256 */
	ext[e ++] = 0x03;
	ext[e ++] = 0x04;                  /* rsa_pkcs1_sha256 */
	ext[e ++] = 0x01;
	ext[e ++] = 0x00;                  /* supported_groups */
	ext[e ++] = 0x0A;
	put16(ext + e, 4);
	e += 2;
	put16(ext + e, 2);
	e += 2;
	put16(ext + e, 0x0017);            /* secp256r1 */
	e += 2;
	ext[e ++] = 0x00;                  /* ec_point_formats */
	ext[e ++] = 0x0B;
	put16(ext + e, 2);
	e += 2;
	ext[e ++] = 1;                     /* uncompressed */
	ext[e ++] = 0;

	put16(b + n, e);
	n += 2;
	memcpy(b + n, ext, e);
	n += e;
	return hs_send(t, 1, b, n);
}

/* ---- server messages ---- */

static int
parse_serverhello(ts_conn *t, const unsigned char *b, size_t len, unsigned *suite)
{
	size_t pos, sid;

	if (len < 2 + 32 + 1) {
		return TS_ERR_PROTOCOL;
	}
	if (get16(b) != 0x0303) {
		return TS_ERR_UNSUPPORTED;
	}
	memcpy(t->server_random, b + 2, 32);
	pos = 34;
	sid = b[pos ++];
	if (sid > 32 || pos + sid + 3 > len) {
		return TS_ERR_PROTOCOL;
	}
	pos += sid;
	*suite = get16(b + pos);
	pos += 2;
	if (*suite != 0xC02B && *suite != 0xC02F && *suite != 0x009C) {
		return TS_ERR_UNSUPPORTED;
	}
	if (b[pos ++] != 0) {
		return TS_ERR_UNSUPPORTED;
	}
	return TS_OK;
}

static int
parse_certificate(ts_conn *t, const unsigned char *b, size_t len)
{
	size_t clen;

	if (len < 6) {
		return TS_ERR_PROTOCOL;
	}
	if (get24(b) + 3 != len) {
		return TS_ERR_PROTOCOL;
	}
	clen = get24(b + 3);
	if (clen == 0 || 6 + clen > len) {
		return TS_ERR_PROTOCOL;
	}
	/*
	 * The public key is kept in the certificate copy, not in the
	 * handshake reassembly buffer (which gets shifted around as
	 * more messages are read).
	 */
	if (clen > sizeof t->cert) {
		return TS_ERR_CERTIFICATE;
	}
	memcpy(t->cert, b + 6, clen);
	if (!ts_x509_get_pkey(t->cert, clen, &t->pkey)) {
		return TS_ERR_CERTIFICATE;
	}
	return TS_OK;
}

static int
parse_ske(ts_conn *t, const unsigned char *b, size_t len)
{
	unsigned char hash[32];
	const unsigned char *pt, *sig;
	const unsigned char *order;
	size_t ptlen, siglen, hlen, olen, glen, xoff, xlen;
	unsigned char key[66];
	unsigned char mask;

	if (len < 4 + 1 + 4) {
		return TS_ERR_PROTOCOL;
	}
	if (b[0] != 3 || get16(b + 1) != 0x0017) {
		return TS_ERR_UNSUPPORTED;     /* only named curve P-256 */
	}
	ptlen = b[3];
	if (ptlen < 65 || 4 + ptlen + 4 > len) {
		return TS_ERR_PROTOCOL;
	}
	pt = b + 4;
	if (pt[0] != 0x04) {
		return TS_ERR_UNSUPPORTED;     /* uncompressed points only */
	}
	hlen = 4 + ptlen;                  /* signed ServerECDHParams */
	if (b[hlen] != 4) {                /* SHA-256 only */
		return TS_ERR_UNSUPPORTED;
	}
	siglen = get16(b + hlen + 2);
	if (hlen + 4 + siglen != len) {
		return TS_ERR_PROTOCOL;
	}
	sig = b + hlen + 4;

	/* hash = SHA256(client_random || server_random || params) */
	{
		ts_sha256_ctx sc;

		ts_sha256_init(&sc);
		ts_sha256_update(&sc, t->client_random, 32);
		ts_sha256_update(&sc, t->server_random, 32);
		ts_sha256_update(&sc, b, hlen);
		ts_sha256_out(&sc, hash);
	}
	if (b[hlen + 1] == 0x01) {         /* RSA */
		unsigned char out[32];

		if (t->pkey.key_type != TS_KEY_RSA) {
			return TS_ERR_CERTIFICATE;
		}
		if (!br_rsa_i31_pkcs1_vrfy(sig, siglen, BR_HASH_OID_SHA256,
			32, &t->pkey.key.rsa, out)
			|| memcmp(out, hash, 32) != 0)
		{
			return TS_ERR_SIGNATURE;
		}
	} else if (b[hlen + 1] == 0x03) {  /* ECDSA */
		if (t->pkey.key_type != TS_KEY_EC) {
			return TS_ERR_CERTIFICATE;
		}
		if (!br_ecdsa_i31_vrfy_asn1(&br_ec_prime_i31, hash, 32,
			&t->pkey.key.ec, sig, siglen))
		{
			return TS_ERR_SIGNATURE;
		}
	} else {
		return TS_ERR_UNSUPPORTED;
	}

	/* Ephemeral key and pre-master secret (the shared X). */
	order = br_ec_prime_i31.order(BR_EC_secp256r1, &olen);
	mask = 0xFF;
	while (mask >= order[0]) {
		mask >>= 1;
	}
	ts_random(key, olen);
	key[0] &= mask;
	key[olen - 1] |= 0x01;
	br_ec_prime_i31.generator(BR_EC_secp256r1, &glen);
	if (glen != ptlen) {
		return TS_ERR_PROTOCOL;
	}
	memcpy(t->exch, pt, glen);
	if (!br_ec_prime_i31.mul(t->exch, glen, key, olen, BR_EC_secp256r1)) {
		return TS_ERR_PROTOCOL;
	}
	xoff = br_ec_prime_i31.xoff(BR_EC_secp256r1, &xlen);
	memcpy(t->pms, t->exch + xoff, xlen);
	t->pms_len = xlen;
	br_ec_prime_i31.mulgen(t->exch, key, olen, BR_EC_secp256r1);
	t->exch_len = glen;
	return TS_OK;
}

/*
 * Static RSA: build the pre-master secret and encrypt it with the
 * server key (PKCS#1 v1.5, type 2 padding).
 */
static int
make_rsa_pms(ts_conn *t)
{
	unsigned char block[TS_MAXRSA];
	const unsigned char *n = t->pkey.key.rsa.n;
	size_t nlen = t->pkey.key.rsa.nlen;
	size_t u;

	while (nlen > 0 && *n == 0) {
		n ++;
		nlen --;
	}
	if (nlen < 64 || nlen > sizeof block) {
		return TS_ERR_CERTIFICATE;
	}
	t->pms[0] = 0x03;
	t->pms[1] = 0x03;
	ts_random(t->pms + 2, 46);
	t->pms_len = 48;
	block[0] = 0x00;
	block[1] = 0x02;
	ts_random(block + 2, nlen - 51);
	for (u = 2; u < nlen - 49; u ++) {
		if (block[u] == 0) {
			block[u] = 1;
		}
	}
	block[nlen - 49] = 0x00;
	memcpy(block + nlen - 48, t->pms, 48);
	if (!br_rsa_i31_public(block, nlen, &t->pkey.key.rsa)) {
		return TS_ERR_CERTIFICATE;
	}
	memcpy(t->exch, block, nlen);
	t->exch_len = nlen;
	return TS_OK;
}

static int
send_clientkeyexchange(ts_conn *t)
{
	unsigned char b[3 + 512];

	if (t->suite == 0x009C) {
		size_t n = t->exch_len;

		if (n > sizeof b - 2) {
			return TS_ERR_PROTOCOL;
		}
		put16(b, n);
		memcpy(b + 2, t->exch, n);
		return hs_send(t, 16, b, 2 + n);
	} else {
		size_t n = t->exch_len;

		if (n > sizeof b - 1) {
			return TS_ERR_PROTOCOL;
		}
		b[0] = (unsigned char)n;
		memcpy(b + 1, t->exch, n);
		return hs_send(t, 16, b, 1 + n);
	}
}

static void
compute_keys(ts_conn *t)
{
	unsigned char seed[64], kb[40];

	memcpy(seed, t->client_random, 32);
	memcpy(seed + 32, t->server_random, 32);
	ts_prf(t->pms, t->pms_len, "master secret", seed, 64, t->master, 48);
	memcpy(seed, t->server_random, 32);
	memcpy(seed + 32, t->client_random, 32);
	ts_prf(t->master, 48, "key expansion", seed, 64, kb, sizeof kb);
	memcpy(t->wkey, kb, 16);
	memcpy(t->rkey, kb + 16, 16);
	memcpy(t->wiv, kb + 32, 4);
	memcpy(t->riv, kb + 36, 4);
	ts_aes_init(&t->waes, t->wkey);
	ts_aes_init(&t->raes, t->rkey);
	gcm_h(&t->waes, t->wh);
	gcm_h(&t->raes, t->rh);
}

static void
hash_snapshot(ts_conn *t, unsigned char out[32])
{
	ts_sha256_ctx sc = t->hs;

	ts_sha256_out(&sc, out);
}

static int
send_finished(ts_conn *t, const char *label)
{
	unsigned char th[32], vd[12];

	hash_snapshot(t, th);
	ts_prf(t->master, 48, label, th, 32, vd, sizeof vd);
	return hs_send(t, 20, vd, sizeof vd);
}

/* ---- connection setup ---- */

ts_conn *
ts_new(const char *server_name, void *ioctx,
	int (*ioread)(void *ctx, void *buf, size_t len),
	int (*iowrite)(void *ctx, const void *buf, size_t len))
{
	ts_conn *t;
	size_t n;

	n = 0;
	if (server_name != NULL) {
		n = strlen(server_name);
		if (n > 255) {
			return NULL;
		}
	}
	t = calloc(1, sizeof *t);
	if (t == NULL) {
		return NULL;
	}
	t->ioctx = ioctx;
	t->ioread = ioread;
	t->iowrite = iowrite;
	if (n > 0) {
		memcpy(t->sni, server_name, n + 1);
	}
	ts_sha256_init(&t->hs);
	ts_random(t->client_random, 32);
	return t;
}

enum {
	HS_CH = 0, HS_SH, HS_CERT, HS_SKE, HS_TAIL, HS_CERT0,
	HS_CKE, HS_CCS, HS_FIN, HS_SRV_CCS, HS_SRV_FIN, HS_DONE
};

/*
 * Run the handshake state machine as far as possible without
 * blocking. Each helper either makes progress or reports
 * TS_WANT_READ/TS_WANT_WRITE, which is passed to the caller.
 */
int
ts_handshake(ts_conn *t)
{
	int r;

	if (t->err != 0) {
		return t->err;
	}
	for (;;) {
		unsigned type;
		const unsigned char *body;
		size_t blen;

		r = rec_flush(t);
		if (r != TS_OK) {
			return r;
		}
		switch (t->hs_state) {
		case HS_CH:
			r = send_clienthello(t);
			if (r != TS_OK) {
				return r;
			}
			t->hs_state = HS_SH;
			break;

		case HS_SH:
			r = hs_next(t, &type, &body, &blen);
			if (r != TS_OK) {
				return r;
			}
			if (type != 2) {
				t->err = TS_ERR_PROTOCOL;
				return t->err;
			}
			r = parse_serverhello(t, body, blen, &t->suite);
			if (r != TS_OK) {
				t->err = r;
				return r;
			}
			hs_skip(t, 4 + blen);
			t->hs_state = HS_CERT;
			break;

		case HS_CERT:
			r = hs_next(t, &type, &body, &blen);
			if (r != TS_OK) {
				return r;
			}
			if (type != 11) {
				t->err = TS_ERR_PROTOCOL;
				return t->err;
			}
			r = parse_certificate(t, body, blen);
			if (r != TS_OK) {
				t->err = r;
				return r;
			}
			hs_skip(t, 4 + blen);
			t->hs_state = t->suite == 0x009C ? HS_TAIL : HS_SKE;
			break;

		case HS_SKE:
			r = hs_next(t, &type, &body, &blen);
			if (r != TS_OK) {
				return r;
			}
			if (type != 12) {
				t->err = TS_ERR_PROTOCOL;
				return t->err;
			}
			r = parse_ske(t, body, blen);
			if (r != TS_OK) {
				t->err = r;
				return r;
			}
			hs_skip(t, 4 + blen);
			t->hs_state = HS_TAIL;
			break;

		case HS_TAIL:
			r = hs_next(t, &type, &body, &blen);
			if (r != TS_OK) {
				return r;
			}
			hs_skip(t, 4 + blen);
			if (type == 13) {
				t->seen_cr = 1;
				break;
			}
			if (type != 14) {
				t->err = TS_ERR_PROTOCOL;
				return t->err;
			}
			if (t->suite == 0x009C) {
				r = make_rsa_pms(t);
				if (r != TS_OK) {
					t->err = r;
					return r;
				}
			}
			t->hs_state = t->seen_cr ? HS_CERT0 : HS_CKE;
			break;

		case HS_CERT0:
			r = hs_send(t, 11, "\x00\x00\x00", 3);
			if (r != TS_OK) {
				return r;
			}
			t->hs_state = HS_CKE;
			break;

		case HS_CKE:
			r = send_clientkeyexchange(t);
			if (r != TS_OK) {
				return r;
			}
			t->hs_state = HS_CCS;
			break;

		case HS_CCS:
			compute_keys(t);
			r = rec_queue(t, 20, "\x01", 1);
			if (r != TS_OK) {
				return r;
			}
			t->enc_out = 1;
			t->seq_out = 0;
			t->hs_state = HS_FIN;
			break;

		case HS_FIN:
			r = send_finished(t, "client finished");
			if (r != TS_OK) {
				return r;
			}
			t->hs_state = HS_SRV_CCS;
			break;

		case HS_SRV_CCS:
			r = rec_next(t);
			if (r != TS_OK) {
				return r;
			}
			if (t->rtype == 21) {
				t->err = TS_ERR_ALERT;
				return t->err;
			}
			if (t->rtype != 20 || t->rlen != 1
				|| t->rbuf[0] != 1)
			{
				t->err = TS_ERR_PROTOCOL;
				return t->err;
			}
			t->enc_in = 1;
			t->seq_in = 0;
			t->hs_state = HS_SRV_FIN;
			break;

		case HS_SRV_FIN:
			r = rec_next(t);
			if (r != TS_OK) {
				return r;
			}
			if (t->rtype != 22 || t->rlen != 16
				|| t->rbuf[0] != 20 || get24(t->rbuf + 1) != 12)
			{
				t->err = TS_ERR_PROTOCOL;
				return t->err;
			}
			{
				unsigned char th[32], vd[12];

				hash_snapshot(t, th);
				ts_prf(t->master, 48, "server finished",
					th, 32, vd, sizeof vd);
				if (memcmp(t->rbuf + 4, vd, sizeof vd) != 0) {
					t->err = TS_ERR_SIGNATURE;
					return t->err;
				}
				ts_sha256_update(&t->hs, t->rbuf, t->rlen);
			}
			t->hs_state = HS_DONE;
			break;

		default:
			return TS_OK;
		}
	}
}

/* ---- application data ---- */

int
ts_write(ts_conn *t, const void *buf, size_t len)
{
	int r;

	if (t->err != 0) {
		return t->err;
	}
	if (t->hs_state != HS_DONE) {
		t->err = TS_ERR_PROTOCOL;
		return t->err;
	}
	r = rec_flush(t);
	if (r != TS_OK) {
		return r;
	}
	if (len > TS_MAXPLAIN) {
		len = TS_MAXPLAIN;
	}
	r = rec_queue(t, 23, buf, len);
	if (r != TS_OK) {
		return r;
	}
	(void)rec_flush(t);
	return (int)len;
}

int
ts_read(ts_conn *t, void *buf, size_t len)
{
	int r;

	if (t->err != 0) {
		return t->err;
	}
	if (t->hs_state != HS_DONE) {
		t->err = TS_ERR_PROTOCOL;
		return t->err;
	}
	if (t->eof) {
		return 0;
	}
	r = rec_flush(t);
	if (r != TS_OK) {
		return r;
	}
	while (t->app_pos == t->app_len) {
		r = rec_next(t);
		if (r != TS_OK) {
			return r;
		}
		if (t->rtype == 23) {
			memcpy(t->app, t->rbuf, t->rlen);
			t->app_len = t->rlen;
			t->app_pos = 0;
			break;
		}
		if (t->rtype == 21) {
			if (t->rlen >= 2 && t->rbuf[0] == 1
				&& t->rbuf[1] == 0)
			{
				t->eof = 1;
				return 0;
			}
			t->err = TS_ERR_ALERT;
			return t->err;
		}
		if (t->rtype == 22) {
			continue;         /* HelloRequest, ignored */
		}
		t->err = TS_ERR_PROTOCOL;
		return t->err;
	}
	{
		size_t n = t->app_len - t->app_pos;

		if (n > len) {
			n = len;
		}
		memcpy(buf, t->app + t->app_pos, n);
		t->app_pos += n;
		return (int)n;
	}
}

int
ts_flush(ts_conn *t)
{
	if (t->err != 0) {
		return t->err;
	}
	return rec_flush(t);
}

int
ts_error(ts_conn *t)
{
	return t->err;
}

const char *
ts_strerror(int err)
{
	switch (err) {
	case TS_OK: return "ok";
	case TS_WANT_READ: return "want read";
	case TS_WANT_WRITE: return "want write";
	case TS_ERR_IO: return "i/o error";
	case TS_ERR_MEMORY: return "out of memory";
	case TS_ERR_PROTOCOL: return "protocol error";
	case TS_ERR_UNSUPPORTED: return "unsupported algorithm";
	case TS_ERR_CERTIFICATE: return "bad certificate";
	case TS_ERR_SIGNATURE: return "bad signature";
	case TS_ERR_ALERT: return "server alert";
	}
	return "unknown error";
}

void
ts_free(ts_conn *t)
{
	free(t);
}
