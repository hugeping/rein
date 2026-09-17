/*
 * Crypto primitives for tinytls: SHA-256, AES-128/CTR, GHASH, the
 * TLS 1.2 PRF (with HMAC-SHA256) and the weak RNG.
 */

#include <string.h>
#include <time.h>

#include "ts_priv.h"

/*
 * SHA-256 (FIPS 180-4). Written for tinytls; only the hash itself is
 * needed here, no streaming-state export or vtable plumbing.
 */

static const uint32_t K[64] = {
	0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
	0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
	0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
	0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
	0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
	0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
	0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
	0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
	0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
	0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
	0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
	0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
	0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
	0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
	0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
	0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
};

static uint32_t
rotr(uint32_t x, int n)
{
	return (x >> n) | (x << (32 - n));
}

static void
sha256_blocks(uint32_t *h, const unsigned char *data, size_t count)
{
	size_t u;

	for (u = 0; u < count; u ++) {
		uint32_t w[64], a, b, c, d, e, f, g, hh;
		int i;

		for (i = 0; i < 16; i ++) {
			w[i] = ((uint32_t)data[4 * i] << 24)
				| ((uint32_t)data[4 * i + 1] << 16)
				| ((uint32_t)data[4 * i + 2] << 8)
				| (uint32_t)data[4 * i + 3];
		}
		for (i = 16; i < 64; i ++) {
			uint32_t s0, s1;

			s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18)
				^ (w[i - 15] >> 3);
			s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19)
				^ (w[i - 2] >> 10);
			w[i] = w[i - 16] + s0 + w[i - 7] + s1;
		}
		a = h[0];
		b = h[1];
		c = h[2];
		d = h[3];
		e = h[4];
		f = h[5];
		g = h[6];
		hh = h[7];
		for (i = 0; i < 64; i ++) {
			uint32_t s1, ch, t1, s0, maj, t2;

			s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
			ch = (e & f) ^ (~e & g);
			t1 = hh + s1 + ch + K[i] + w[i];
			s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
			maj = (a & b) ^ (a & c) ^ (b & c);
			t2 = s0 + maj;
			hh = g;
			g = f;
			f = e;
			e = d + t1;
			d = c;
			c = b;
			b = a;
			a = t1 + t2;
		}
		h[0] += a;
		h[1] += b;
		h[2] += c;
		h[3] += d;
		h[4] += e;
		h[5] += f;
		h[6] += g;
		h[7] += hh;
		data += 64;
	}
}

void
ts_sha256_init(ts_sha256_ctx *ctx)
{
	ctx->val[0] = 0x6A09E667;
	ctx->val[1] = 0xBB67AE85;
	ctx->val[2] = 0x3C6EF372;
	ctx->val[3] = 0xA54FF53A;
	ctx->val[4] = 0x510E527F;
	ctx->val[5] = 0x9B05688C;
	ctx->val[6] = 0x1F83D9AB;
	ctx->val[7] = 0x5BE0CD19;
	ctx->count = 0;
}

void
ts_sha256_update(ts_sha256_ctx *ctx, const void *data, size_t len)
{
	const unsigned char *p = data;
	size_t ptr = (size_t)ctx->count & 63;

	ctx->count += len;
	if (ptr > 0) {
		size_t clen = 64 - ptr;

		if (len < clen) {
			memcpy(ctx->buf + ptr, p, len);
			return;
		}
		memcpy(ctx->buf + ptr, p, clen);
		sha256_blocks(ctx->val, ctx->buf, 1);
		p += clen;
		len -= clen;
	}
	if (len >= 64) {
		size_t n = len >> 6;

		sha256_blocks(ctx->val, p, n);
		p += n << 6;
		len &= 63;
	}
	if (len > 0) {
		memcpy(ctx->buf, p, len);
	}
}

void
ts_sha256_out(const ts_sha256_ctx *ctx, void *out)
{
	ts_sha256_ctx sc = *ctx;
	unsigned char *dst = out;
	uint64_t bits;
	size_t ptr;
	unsigned char pad[72];
	size_t padlen;
	int i;

	bits = sc.count << 3;
	ptr = (size_t)sc.count & 63;
	padlen = (ptr < 56 ? 56 : 120) - ptr;
	memset(pad, 0, padlen);
	pad[0] = 0x80;
	for (i = 0; i < 8; i ++) {
		pad[padlen + i] = (unsigned char)(bits >> (56 - 8 * i));
	}
	ts_sha256_update(&sc, pad, padlen + 8);
	for (i = 0; i < 8; i ++) {
		dst[4 * i] = (unsigned char)(sc.val[i] >> 24);
		dst[4 * i + 1] = (unsigned char)(sc.val[i] >> 16);
		dst[4 * i + 2] = (unsigned char)(sc.val[i] >> 8);
		dst[4 * i + 3] = (unsigned char)sc.val[i];
	}
}


/*
 * AES-128 and CTR mode. Written for tinytls: table-based AES, no
 * constant-time claim, no decryption (GCM only needs encryption).
 *
 * ts_aes_ctr_xor() XORs the keystream into the buffer, and the
 * counter block is iv[12] followed by the big-endian counter.
 */

static const unsigned char sbox[256] = {
	0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5,
	0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
	0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0,
	0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
	0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC,
	0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
	0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A,
	0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
	0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0,
	0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
	0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B,
	0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
	0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85,
	0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
	0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5,
	0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
	0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17,
	0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
	0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88,
	0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
	0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C,
	0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
	0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9,
	0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
	0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6,
	0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
	0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E,
	0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
	0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94,
	0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
	0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68,
	0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16
};

static const unsigned char rcon[11] = {
	0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36
};

static void
add_round_key(unsigned char *s, const unsigned char *rk)
{
	int i;

	for (i = 0; i < 16; i ++) {
		s[i] ^= rk[i];
	}
}

static void
sub_bytes(unsigned char *s)
{
	int i;

	for (i = 0; i < 16; i ++) {
		s[i] = sbox[s[i]];
	}
}

static void
shift_rows(unsigned char *s)
{
	unsigned char t;

	t = s[1];
	s[1] = s[5];
	s[5] = s[9];
	s[9] = s[13];
	s[13] = t;
	t = s[2];
	s[2] = s[10];
	s[10] = t;
	t = s[6];
	s[6] = s[14];
	s[14] = t;
	t = s[15];
	s[15] = s[11];
	s[11] = s[7];
	s[7] = s[3];
	s[3] = t;
}

static unsigned char
xtime(unsigned char x)
{
	return (unsigned char)((x << 1) ^ ((x >> 7) * 0x1B));
}

static void
mix_columns(unsigned char *s)
{
	int i;

	for (i = 0; i < 16; i += 4) {
		unsigned char a0, a1, a2, a3, t;

		a0 = s[i];
		a1 = s[i + 1];
		a2 = s[i + 2];
		a3 = s[i + 3];
		t = a0 ^ a1 ^ a2 ^ a3;
		s[i] = a0 ^ t ^ xtime(a0 ^ a1);
		s[i + 1] = a1 ^ t ^ xtime(a1 ^ a2);
		s[i + 2] = a2 ^ t ^ xtime(a2 ^ a3);
		s[i + 3] = a3 ^ t ^ xtime(a3 ^ a0);
	}
}

void
ts_aes_init(ts_aes_ctx *ctx, const void *key)
{
	unsigned char *rk = ctx->rk;
	int i;

	memcpy(rk, key, 16);
	for (i = 16; i < 176; i += 4) {
		unsigned char t[4];

		memcpy(t, rk + i - 4, 4);
		if ((i & 15) == 0) {
			unsigned char t0 = t[0];

			t[0] = sbox[t[1]] ^ rcon[i >> 4];
			t[1] = sbox[t[2]];
			t[2] = sbox[t[3]];
			t[3] = sbox[t0];
		}
		rk[i] = rk[i - 16] ^ t[0];
		rk[i + 1] = rk[i - 15] ^ t[1];
		rk[i + 2] = rk[i - 14] ^ t[2];
		rk[i + 3] = rk[i - 13] ^ t[3];
	}
}

static void
aes_encrypt_block(const unsigned char *rk, unsigned char out[16],
	const unsigned char in[16])
{
	unsigned char s[16];
	int r;

	memcpy(s, in, 16);
	add_round_key(s, rk);
	for (r = 1; r < 10; r ++) {
		sub_bytes(s);
		shift_rows(s);
		mix_columns(s);
		add_round_key(s, rk + 16 * r);
	}
	sub_bytes(s);
	shift_rows(s);
	add_round_key(s, rk + 160);
	memcpy(out, s, 16);
}

void
ts_aes_ctr_xor(const ts_aes_ctx *ctx, const unsigned char iv[12],
	uint32_t cc, void *data, size_t len)
{
	unsigned char *p = data;
	unsigned char blk[16], ks[16];
	size_t u;

	while (len > 0) {
		size_t n = len < 16 ? len : 16;

		memcpy(blk, iv, 12);
		blk[12] = (unsigned char)(cc >> 24);
		blk[13] = (unsigned char)(cc >> 16);
		blk[14] = (unsigned char)(cc >> 8);
		blk[15] = (unsigned char)cc;
		aes_encrypt_block(ctx->rk, ks, blk);
		for (u = 0; u < n; u ++) {
			p[u] ^= ks[u];
		}
		p += n;
		len -= n;
		cc ++;
	}
}


/*
 * GHASH for GCM (NIST SP 800-38D). Bit-serial GF(2^128) multiply by
 * the hash key; not constant-time, which is fine for this client.
 */

/*
 * z = z * h in GF(2^128), with the NIST bit ordering (leftmost bit
 * is the coefficient of x^0, so multiplication by x is a right
 * shift with reduction constant 0xE1).
 */
static void
gf_mul(unsigned char z[16], const unsigned char h[16])
{
	unsigned char v[16], t[16];
	int i, j, k;

	memcpy(v, h, 16);
	memset(t, 0, 16);
	for (i = 0; i < 16; i ++) {
		unsigned char zb = z[i];

		for (j = 0; j < 8; j ++) {
			unsigned char carry = 0;
			unsigned char hi;

			if (zb & (unsigned char)(0x80 >> j)) {
				for (k = 0; k < 16; k ++) {
					t[k] ^= v[k];
				}
			}
			hi = (unsigned char)(v[15] & 1);
			for (k = 0; k < 16; k ++) {
				unsigned char nc = (unsigned char)(v[k] & 1);

				v[k] = (unsigned char)((v[k] >> 1)
					| (carry << 7));
				carry = nc;
			}
			v[0] ^= (unsigned char)(hi * 0xE1);
		}
	}
	memcpy(z, t, 16);
}

void
ts_ghash(void *y, const void *h, const void *data, size_t len)
{
	const unsigned char *p = data;
	unsigned char *yp = y;
	unsigned char blk[16];
	int i;

	while (len >= 16) {
		for (i = 0; i < 16; i ++) {
			yp[i] ^= p[i];
		}
		gf_mul(yp, h);
		p += 16;
		len -= 16;
	}
	if (len > 0) {
		memset(blk, 0, 16);
		memcpy(blk, p, len);
		for (i = 0; i < 16; i ++) {
			yp[i] ^= blk[i];
		}
		gf_mul(yp, h);
	}
}


/*
 * HMAC-SHA256, the TLS 1.2 PRF, and a weak random generator (the
 * latter is only meant to keep the handshake running; this client
 * is not secure anyway).
 */

/* ---- weak RNG ---- */

static uint64_t rng_state;

static uint64_t
rng_next(void)
{
	uint64_t x;

	x = rng_state;
	x ^= x << 13;
	x ^= x >> 7;
	x ^= x << 17;
	rng_state = x;
	return x;
}

void
ts_random(void *buf, size_t len)
{
	unsigned char *p = buf;

	if (rng_state == 0) {
		uint64_t x;

		x = (uint64_t)time(NULL);
		x ^= (uint64_t)(uintptr_t)&rng_state << 17;
		x ^= (uint64_t)(uintptr_t)buf << 33;
		rng_state = x | 1;
		rng_next();
	}
	while (len > 0) {
		uint64_t x = rng_next();
		size_t n = len < 8 ? len : 8;

		memcpy(p, &x, n);
		p += n;
		len -= n;
	}
}

/* ---- HMAC-SHA256 ---- */

typedef struct {
	unsigned char ipad[64];
	unsigned char opad[64];
} ts_hmac_key;

static void
hmac_key(ts_hmac_key *hk, const void *key, size_t klen)
{
	unsigned char k[64];
	size_t i;

	memset(k, 0, sizeof k);
	if (klen > sizeof k) {
		ts_sha256_ctx sc;

		ts_sha256_init(&sc);
		ts_sha256_update(&sc, key, klen);
		ts_sha256_out(&sc, k);
	} else {
		memcpy(k, key, klen);
	}
	for (i = 0; i < sizeof k; i ++) {
		hk->ipad[i] = k[i] ^ 0x36;
		hk->opad[i] = k[i] ^ 0x5C;
	}
}

static void
hmac_run(const ts_hmac_key *hk,
	const void *a, size_t alen,
	const void *b, size_t blen,
	const void *c, size_t clen,
	unsigned char out[32])
{
	ts_sha256_ctx sc;
	unsigned char tmp[32];

	ts_sha256_init(&sc);
	ts_sha256_update(&sc, hk->ipad, sizeof hk->ipad);
	if (alen > 0) {
		ts_sha256_update(&sc, a, alen);
	}
	if (blen > 0) {
		ts_sha256_update(&sc, b, blen);
	}
	if (clen > 0) {
		ts_sha256_update(&sc, c, clen);
	}
	ts_sha256_out(&sc, tmp);
	ts_sha256_init(&sc);
	ts_sha256_update(&sc, hk->opad, sizeof hk->opad);
	ts_sha256_update(&sc, tmp, sizeof tmp);
	ts_sha256_out(&sc, out);
}


/* ---- TLS 1.2 PRF ---- */

static void
hmac_plain(const ts_hmac_key *hk, const void *data, size_t len,
	unsigned char out[32])
{
	hmac_run(hk, data, len, NULL, 0, NULL, 0, out);
}

void
ts_prf(const void *secret, size_t slen, const char *label,
	const void *seed, size_t seed_len, void *out, size_t out_len)
{
	ts_hmac_key hk;
	unsigned char a[32], block[32];
	size_t llen;
	unsigned char *dst;

	llen = strlen(label);
	hmac_key(&hk, secret, slen);
	hmac_run(&hk, label, llen, seed, seed_len, NULL, 0, a);
	dst = out;
	while (out_len > 0) {
		size_t n;

		hmac_run(&hk, a, sizeof a, label, llen, seed, seed_len,
			block);
		n = out_len < sizeof block ? out_len : sizeof block;
		memcpy(dst, block, n);
		dst += n;
		out_len -= n;
		hmac_plain(&hk, a, sizeof a, a);
	}
}

