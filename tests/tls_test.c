/*
 * Headless tests for src/tls (TinyTLS): crypto known-answer vectors,
 * X.509 parsing, record layer and a golden replay of a captured
 * TLS 1.2 session.
 *
 * Build and run: sh tests/run.sh (or cc -O2 -I src/tls ... by hand).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * The test provides its own ts_random (a deterministic stream), so
 * that the captured session can be replayed byte for byte.
 */
#include "tinytls.c"     /* calls ts_random (declared in ts_priv.h) */
#include "ts_x509.c"
#define ts_random ts_random_lib
#include "ts_crypto.c"    /* the library's ts_random becomes ts_random_lib */
#undef ts_random

#include "ts_cert.c"

#include "tls_session.h"

static uint64_t rng_state;
static int checks, failures;

static void
rng_reset(void)
{
	rng_state = 0x9E3779B97F4A7C15ULL;
}

void
ts_random(void *buf, size_t len)
{
	unsigned char *p = buf;

	while (len > 0) {
		uint64_t x = rng_state;
		size_t n;

		x ^= x << 13;
		x ^= x >> 7;
		x ^= x << 17;
		rng_state = x;
		n = len < 8 ? len : 8;
		memcpy(p, &x, n);
		p += n;
		len -= n;
	}
}

static void
chk(int cond, const char *name)
{
	checks ++;
	if (cond) {
		printf("  ok   %s\n", name);
	} else {
		failures ++;
		printf("  FAIL %s\n", name);
	}
}

static int
unhex(const char *hex, unsigned char *out, size_t max)
{
	size_t n = 0;

	while (hex[0] != 0 && hex[1] != 0) {
		unsigned v;

		if (n >= max || sscanf(hex, "%2x", &v) != 1) {
			return -1;
		}
		out[n ++] = (unsigned char)v;
		hex += 2;
	}
	return (int)n;
}

/* ---- mock transport ---- */

struct mock {
	const unsigned char *in;
	size_t in_len, in_pos;
	unsigned char out[20000];
	size_t out_len;
	int block;
	int eof;
};

static int
mock_read(void *ctx, void *buf, size_t len)
{
	struct mock *m = ctx;
	size_t n = m->in_len - m->in_pos;

	if (n == 0) {
		return m->eof ? -1 : 0;
	}
	if (n > len) {
		n = len;
	}
	memcpy(buf, m->in + m->in_pos, n);
	m->in_pos += n;
	return (int)n;
}

static int
mock_write(void *ctx, const void *buf, size_t len)
{
	struct mock *m = ctx;

	if (m->block) {
		return 0;
	}
	if (m->out_len + len > sizeof m->out) {
		return -1;
	}
	memcpy(m->out + m->out_len, buf, len);
	m->out_len += len;
	return (int)len;
}

/* ---- SHA-256 ---- */

static void
test_sha256(void)
{
	static const char *v[][2] = {
		{ "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934"
			"ca495991b7852b855" },
		{ "abc", "ba7816bf8f01cfea414140de5dae2223b00361a39617"
			"7a9cb410ff61f20015ad" },
		{ "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
			"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6eced"
			"d419db06c1" }
	};
	ts_sha256_ctx sc;
	unsigned char out[32], want[32];
	size_t i;

	printf("# sha256\n");
	for (i = 0; i < 3; i ++) {
		ts_sha256_init(&sc);
		ts_sha256_update(&sc, v[i][0], strlen(v[i][0]));
		ts_sha256_out(&sc, out);
		unhex(v[i][1], want, sizeof want);
		chk(memcmp(out, want, 32) == 0, "vector");
	}
	/* chunked updates must match a single one */
	{
		const char *msg = "abcdbcdecdefdefgefghfghighijhijkijkljkl"
			"mklmnlmnomnopnopq";
		size_t len = strlen(msg);
		unsigned char one[32], chunked[32];

		ts_sha256_init(&sc);
		ts_sha256_update(&sc, msg, len);
		ts_sha256_out(&sc, one);
		ts_sha256_init(&sc);
		for (i = 0; i < len; i ++) {
			ts_sha256_update(&sc, msg + i, 1);
		}
		ts_sha256_out(&sc, chunked);
		chk(memcmp(one, chunked, 32) == 0, "chunked");
	}
}

/* ---- HMAC-SHA256 (RFC 4231) and the TLS 1.2 PRF ---- */

static void
test_hmac_prf(void)
{
	static const char *keys[3] = {
		"0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b",
		"4a656665",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	};
	static const char *data[3] = {
		"4869205468657265",
		"7768617420646f2079612077616e7420666f72206e6f7468696e673f",
		"dddddddddddddddddddddddddddddddddddddddddddddddddd""dddddddddddddddddddddddddddddddddddddddddddddddddd"
	};
	static const char *want[3] = {
		"b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
		"5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
		"773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"
	};
	ts_hmac_key hk;
	unsigned char k[64], d[64], out[32], w[32];
	size_t i;

	printf("# hmac-sha256\n");
	for (i = 0; i < 3; i ++) {
		int kl = unhex(keys[i], k, sizeof k);
		int dl = unhex(data[i], d, sizeof d);

		hmac_key(&hk, k, (size_t)kl);
		hmac_run(&hk, d, (size_t)dl, NULL, 0, NULL, 0, out);
		unhex(want[i], w, sizeof w);
		chk(memcmp(out, w, 32) == 0, "vector");
	}
	/* PRF: P_SHA256(0..47, "master secret", 0..31), 100 bytes,
	 * computed with an independent implementation */
	{
		unsigned char secret[48], seed[32];
		unsigned char prf[100], w[100];
		const char *hex = "b13738c253eab875ef632b7e74b73860146138f0"
			"e10026f0f6087f916a7935a94deaba1210f914c474c8b0635"
			"62e16f4ee974d40ae62b554203ce342c433fe1e90084cf18"
			"37d913fcced192af864b94212f1f912762eba68e07fd8f3"
			"27c3a37b28773294";

		printf("# prf\n");
		for (i = 0; i < 48; i ++) {
			secret[i] = (unsigned char)i;
		}
		for (i = 0; i < 32; i ++) {
			seed[i] = (unsigned char)i;
		}
		ts_prf(secret, 48, "master secret", seed, 32, prf, 100);
		unhex(hex, w, sizeof w);
		chk(memcmp(prf, w, 100) == 0, "p_sha256");
	}
}

/* ---- AES-128-CTR (NIST SP 800-38A F.5.1) and GCM ---- */

static void
test_aes_gcm(void)
{
	static const char *key = "2b7e151628aed2a6abf7158809cf4f3c";
	static const char *pt = "6bc1bee22e409f96e93d7e117393172a"
		"ae2d8a571e03ac9c9eb76fac45af8e51"
		"30c81c46a35ce411e5fbc1191a0a52ef"
		"f69f2445df4f9b17ad2b417be66c3710";
	static const char *ct = "874d6191b620e3261bef6864990db6ce"
		"9806f66b7970fdff8617187bb9fffdff"
		"5ae4df3edbd5d35e5b4f09020db03eab"
		"1e031dda2fbe03d1792170a0f3009cee";
	unsigned char k[16], iv[12], buf[64], want[64];
	ts_aes_ctx aes;

	printf("# aes-128-ctr\n");
	unhex(key, k, sizeof k);
	unhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", iv, sizeof iv);
	unhex(pt, buf, sizeof buf);
	unhex(ct, want, sizeof want);
	ts_aes_init(&aes, k);
	ts_aes_ctr_xor(&aes, iv, 0xfcfdfeffu, buf, 64);
	chk(memcmp(buf, want, 64) == 0, "nist f.5.1");

	printf("# gcm\n");
	/* case 2: empty plaintext and AAD */
	{
		unsigned char tag[16], w[16], h[16];
		unsigned char zkey[16], nonce[12];

		memset(zkey, 0, sizeof zkey);
		memset(nonce, 0, sizeof nonce);
		ts_aes_init(&aes, zkey);
		gcm_h(&aes, h);
		gcm_tag(&aes, h, nonce, NULL, 0, NULL, 0, tag);
		unhex("58e2fccefa7e3061367f1d57a4e7455a", w, sizeof w);
		chk(memcmp(tag, w, 16) == 0, "tag only");
	}
	/* case 3: one zero block */
	{
		unsigned char tag[16], w[16], h[16];
		unsigned char zkey[16], nonce[12], blk[16], wct[16];

		memset(zkey, 0, sizeof zkey);
		memset(nonce, 0, sizeof nonce);
		memset(blk, 0, sizeof blk);
		ts_aes_init(&aes, zkey);
		gcm_h(&aes, h);
		ts_aes_ctr_xor(&aes, nonce, 2, blk, 16);
		gcm_tag(&aes, h, nonce, NULL, 0, blk, 16, tag);
		unhex("0388dace60b6a392f328c2b971b2fe78", wct, sizeof wct);
		unhex("ab6e47d42cec13bdf53a67b21257bddf", w, sizeof w);
		chk(memcmp(blk, wct, 16) == 0 && memcmp(tag, w, 16) == 0,
			"one block");
	}
	/* case 4: 60 bytes of plaintext and 20 bytes of AAD */
	{
		unsigned char k2[16], nonce[12], aad[20], p2[60], wct[60];
		unsigned char tag[16], w[16], h[16];

		unhex("feffe9928665731c6d6a8f9467308308", k2, sizeof k2);
		unhex("cafebabefacedbaddecaf888", nonce, sizeof nonce);
		unhex("feedfacedeadbeeffeedfacedeadbeefabaddad2", aad,
			sizeof aad);
		unhex("d9313225f88406e5a55909c5aff5269a"
			"86a7a9531534f7da2e4c303d8a318a72"
			"1c3c0c95956809532fcf0e2449a6b525"
			"b16aedf5aa0de657ba637b39", p2, sizeof p2);
		unhex("42831ec2217774244b7221b784d0d49c"
			"e3aa212f2c02a4e035c17e2329aca12e"
			"21d514b25466931c7d8f6a5aac84aa05"
			"1ba30b396a0aac973d58e091", wct, sizeof wct);
		unhex("5bc94fbc3221a5db94fae95ae7121a47", w, sizeof w);
		ts_aes_init(&aes, k2);
		gcm_h(&aes, h);
		ts_aes_ctr_xor(&aes, nonce, 2, p2, 60);
		gcm_tag(&aes, h, nonce, aad, sizeof aad, p2, 60, tag);
		chk(memcmp(p2, wct, 60) == 0 && memcmp(tag, w, 16) == 0,
			"aad and partial block");
	}
}

/* ---- record layer ---- */

static void
set_writer(ts_conn *t, struct mock *m)
{
	static const unsigned char key[16] = "0123456789abcdef";
	static const unsigned char iv[4] = "wxyz";

	memset(t, 0, sizeof *t);
	t->ioctx = m;
	t->iowrite = mock_write;
	t->hs_state = HS_DONE;
	t->enc_out = 1;
	memcpy(t->wkey, key, 16);
	memcpy(t->wiv, iv, 4);
	ts_aes_init(&t->waes, t->wkey);
	gcm_h(&t->waes, t->wh);
}

static void
set_reader(ts_conn *t, struct mock *m)
{
	static const unsigned char key[16] = "0123456789abcdef";
	static const unsigned char iv[4] = "wxyz";

	memset(t, 0, sizeof *t);
	t->ioctx = m;
	t->ioread = mock_read;
	t->hs_state = HS_DONE;
	t->enc_in = 1;
	memcpy(t->rkey, key, 16);
	memcpy(t->riv, iv, 4);
	ts_aes_init(&t->raes, t->rkey);
	gcm_h(&t->raes, t->rh);
}

static void
test_records(void)
{
	struct ts_conn w, r;
	struct mock mw, mr;
	unsigned char buf[64];
	int n;

	printf("# records\n");
	/* round trip */
	memset(&mw, 0, sizeof mw);
	memset(&mr, 0, sizeof mr);
	set_writer(&w, &mw);
	set_reader(&r, &mr);
	n = ts_write(&w, "hello", 5);
	mr.in = mw.out;
	mr.in_len = mw.out_len;
	n = ts_read(&r, buf, sizeof buf);
	chk(n == 5 && memcmp(buf, "hello", 5) == 0, "round trip");
	chk(ts_read(&r, buf, sizeof buf) == TS_WANT_READ, "wait for read");

	/* tampered record is rejected */
	memset(&mw, 0, sizeof mw);
	set_writer(&w, &mw);
	mr.in_pos = 0;
	mr.in_len = 0;
	set_reader(&r, &mr);
	ts_write(&w, "hello", 5);
	mw.out[mw.out_len - 17] ^= 0x01;   /* last ciphertext byte */
	mr.in = mw.out;
	mr.in_len = mw.out_len;
	chk(ts_read(&r, buf, sizeof buf) == TS_ERR_PROTOCOL, "tamper");

	/* close_notify reads as end of stream */
	memset(&mw, 0, sizeof mw);
	set_writer(&w, &mw);
	set_reader(&r, &mr);
	rec_queue(&w, 21, "\x01\x00", 2);
	chk(ts_flush(&w) == TS_OK, "queue close_notify");
	mr.in = mw.out;
	mr.in_len = mw.out_len;
	mr.in_pos = 0;
	{
		int rr = ts_read(&r, buf, sizeof buf);
		if (rr != 0) printf("       close_notify ret %d (%s)\n",
			rr, ts_strerror(rr));
		chk(rr == 0, "close_notify");
	}
	chk(ts_read(&r, buf, sizeof buf) == 0, "eof is sticky");

	/* pending output: the first write is buffered, the next one
	 * waits until the transport accepts the queued record */
	{
		struct mock mb;

		memset(&mb, 0, sizeof mb);
		set_writer(&w, &mb);
		mb.block = 1;
		chk(ts_write(&w, "x", 1) == 1, "buffered write");
		chk(ts_write(&w, "y", 1) == TS_WANT_WRITE, "blocked write");
		mb.block = 0;
		chk(ts_flush(&w) == TS_OK, "flush after unblock");
		chk(ts_write(&w, "z", 1) == 1, "write after flush");
	}
}

/* ---- X.509 ---- */

static void
test_x509(void)
{
	ts_pkey pk;
	unsigned char junk[128];

	printf("# x509\n");
	memset(junk, 0, sizeof junk);
	chk(!ts_x509_get_pkey(junk, sizeof junk, &pk), "reject junk");
	chk(!ts_x509_get_pkey(ts_cert_rsa, sizeof ts_cert_rsa / 2, &pk),
		"reject truncated");

	chk(ts_x509_get_pkey(ts_cert_rsa, sizeof ts_cert_rsa, &pk)
		&& pk.key_type == TS_KEY_RSA, "rsa type");
	chk(pk.key.rsa.nlen == 257 && pk.key.rsa.elen == 3
		&& pk.key.rsa.n[0] == 0x00 && pk.key.rsa.n[1] == 0xC7
		&& pk.key.rsa.n[2] == 0x0A && pk.key.rsa.e[2] == 0x01,
		"rsa key");

	chk(ts_x509_get_pkey(ts_cert_ec, sizeof ts_cert_ec, &pk)
		&& pk.key_type == TS_KEY_EC, "ec type");
	chk(pk.key.ec.curve == BR_EC_secp256r1 && pk.key.ec.qlen == 65
		&& pk.key.ec.q[0] == 0x04, "ec key");
}

/* ---- API guards ---- */

static void
test_api(void)
{
	struct mock m;
	struct ts_conn *t;
	char longname[300];
	unsigned char buf[8];

	printf("# api\n");
	memset(&m, 0, sizeof m);
	memset(longname, 'a', sizeof longname - 1);
	longname[sizeof longname - 1] = 0;
	chk(ts_new(longname, NULL, mock_read, mock_write) == NULL,
		"long server name");
	t = ts_new(NULL, &m, mock_read, mock_write);
	chk(t != NULL && ts_error(t) == TS_OK, "create without sni");
	chk(ts_read(t, buf, sizeof buf) == TS_ERR_PROTOCOL,
		"read before handshake");
	chk(ts_write(t, buf, sizeof buf) == TS_ERR_PROTOCOL,
		"write before handshake");
	chk(strcmp(ts_strerror(TS_ERR_ALERT), "server alert") == 0,
		"strerror");
	ts_free(t);
	{
		struct ts_conn fresh;
		struct mock mf;

		memset(&fresh, 0, sizeof fresh);
		memset(&mf, 0, sizeof mf);
		fresh.ioctx = &mf;
		fresh.iowrite = mock_write;
		chk(ts_flush(&fresh) == TS_OK, "flush");
	}
}

/* ---- limits and malformed input ---- */

static void
test_limits(void)
{
	struct ts_conn w, r, t;
	struct mock mw, mr;
	unsigned char buf[20000];
	size_t i, clen;

	printf("# limits\n");

	/* a static RSA suite requires an RSA certificate: an EC one
	 * must be refused instead of reading the union overlay */
	memset(&t, 0, sizeof t);
	if (ts_x509_get_pkey(ts_cert_ec, sizeof ts_cert_ec, &t.pkey)) {
		chk(make_rsa_pms(&t) == TS_ERR_CERTIFICATE,
			"static rsa needs an rsa certificate");
	} else {
		chk(0, "ec cert parsed");
	}

	/* a record whose plaintext is larger than TS_MAXPLAIN */
	memset(&mw, 0, sizeof mw);
	memset(&mr, 0, sizeof mr);
	set_writer(&w, &mw);
	w.enc_out = 0;
	clen = 17000;
	{
		unsigned char *p = mw.out;

		p[0] = 23;
		p[1] = 3;
		p[2] = 3;
		put16(p + 3, (unsigned)clen);
		memset(p + 5, 0x41, clen);
		mw.out_len = 5 + clen;
	}
	set_reader(&r, &mr);
	r.enc_in = 0;
	mr.in = mw.out;
	mr.in_len = mw.out_len;
	mr.eof = 1;
	chk(ts_read(&r, buf, sizeof buf) == TS_ERR_PROTOCOL,
		"oversized record");

	/* a flood of handshake records must not spin inside ts_read */
	memset(&mw, 0, sizeof mw);
	memset(&mr, 0, sizeof mr);
	set_writer(&w, &mw);
	w.enc_out = 0;
	for (i = 0; i < 8; i ++) {
		static const unsigned char helloreq[4] = { 0, 0, 0, 0 };

		rec_queue(&w, 22, helloreq, 4);
		ts_flush(&w);
	}
	set_reader(&r, &mr);
	r.enc_in = 0;
	mr.in = mw.out;
	mr.in_len = mw.out_len;
	mr.eof = 1;
	chk(ts_read(&r, buf, sizeof buf) == TS_ERR_PROTOCOL,
		"hello request flood");
}

/* ---- client keys and certificates ---- */

static const char *pk8_hex =
	"308187020100301306072a8648ce3d020106082a8648ce3d03010704"
	"6d306b0201010420327316eddd51c7deda65de8e69858da8d939ef8e"
	"15f443c5dd4b9f80ad348e22a14403420004b2c801f537b7fe4877ef"
	"b52377959d3b2dec471038e7a9ecb06b9936d67a3f1d79967a320070"
	"5abdbac43b6b4bf3f8e959df8aa245294b7727caa109409a5a7c";

static const char *sec1_hex =
	"30770201010420327316eddd51c7deda65de8e69858da8d939ef8e15"
	"f443c5dd4b9f80ad348e22a00a06082a8648ce3d030107a144034200"
	"04b2c801f537b7fe4877efb52377959d3b2dec471038e7a9ecb06b99"
	"36d67a3f1d79967a3200705abdbac43b6b4bf3f8e959df8aa245294b"
	"7727caa109409a5a7c";

static const char *pub_hex =
	"04b2c801f537b7fe4877efb52377959d3b2dec471038e7a9ecb06b99"
	"36d67a3f1d79967a3200705abdbac43b6b4bf3f8e959df8aa245294b"
	"7727caa109409a5a7c";

static const char *scalar_hex =
	"327316eddd51c7deda65de8e69858da8d939ef8e15f443c5dd4b9f80"
	"ad348e22";

static void
test_ec_sign(void)
{
	unsigned char d[32], q[65], hash[32], sig[80], sig2[80];
	br_ec_public_key pk;
	size_t siglen, siglen2;

	memset(hash, 0xA5, sizeof hash);
	rng_reset();
	chk(ts_ec_keygen(d, q), "keygen");
	pk.curve = BR_EC_secp256r1;
	pk.q = q;
	pk.qlen = sizeof q;
	chk(ts_ec_sign(d, hash, sig, &siglen), "sign");
	chk(br_ecdsa_i31_vrfy_asn1(&br_ec_prime_i31, hash, 32, &pk,
		sig, siglen), "the signature verifies");
	chk(siglen > 8 && siglen <= 72, "a short DER signature");
	chk(ts_ec_sign(d, hash, sig2, &siglen2), "sign again");
	chk(siglen != siglen2 || memcmp(sig, sig2, siglen) != 0,
		"the random nonce makes the signatures differ");
	hash[0] ^= 1;
	chk(!br_ecdsa_i31_vrfy_asn1(&br_ec_prime_i31, hash, 32, &pk,
		sig, siglen), "a changed hash does not verify");
}

static void
test_ec_key(void)
{
	unsigned char der[160], d[32], q[65], want[32];
	int n;

	rng_reset();
	n = unhex(pk8_hex, der, sizeof der);
	chk(n > 0 && ts_ec_key_parse(der, (size_t)n, d), "PKCS#8 key");
	n = unhex(scalar_hex, want, sizeof want);
	chk(n == 32 && memcmp(d, want, 32) == 0, "the PKCS#8 scalar");
	n = unhex(sec1_hex, der, sizeof der);
	chk(n > 0 && ts_ec_key_parse(der, (size_t)n, d), "SEC1 key");
	chk(memcmp(d, want, 32) == 0, "the SEC1 scalar");
	n = unhex(pub_hex, q, sizeof q);
	chk(br_ec_prime_i31.mulgen(q, d, 32, BR_EC_secp256r1) == 65,
		"the public point");
	{
		unsigned char pub[65];

		n = unhex(pub_hex, pub, sizeof pub);
		chk(n == 65 && memcmp(q, pub, 65) == 0,
			"the scalar matches the openssl key");
	}
	chk(!ts_ec_key_parse((const unsigned char *)"x", 1, d), "junk key");
	n = unhex(sec1_hex, der, sizeof der);
	chk(!ts_ec_key_parse(der, (size_t)n - 3, d), "a truncated key");
}

static void
test_ec_cert(void)
{
	unsigned char cert[1024], key[128], d[32], q[65], hash[32];
	unsigned char back[1024];
	size_t clen, klen, len, n;
	ts_der c;
	const unsigned char *val, *tbs, *bits;
	ts_pkey pk;
	ts_sha256_ctx sc;
	char pem[2048];

	chk(ts_ec_selfsign("example.com", cert, &clen, key, &klen),
		"selfsign");
	chk(clen > 0 && clen < sizeof cert, "a small certificate");
	chk(ts_x509_get_pkey(cert, clen, &pk) && pk.key_type == TS_KEY_EC
		&& pk.key.ec.curve == BR_EC_secp256r1
		&& pk.key.ec.qlen == 65, "the public key parses");
	chk(ts_ec_key_parse(key, klen, d), "the generated key parses");
	chk(br_ec_prime_i31.mulgen(q, d, 32, BR_EC_secp256r1) == 65,
		"the generated public point");
	chk(memcmp(q, pk.key.ec.q, 65) == 0,
		"the key matches the certificate");

	/* the certificate is signed by its own key */
	c.p = cert;
	c.end = cert + clen;
	chk(ts_der_enter(&c, 0x30), "certificate SEQUENCE");
	tbs = c.p;
	chk(ts_der_tlv(&c, 0x30, &val, &len), "tbsCertificate");
	ts_sha256_init(&sc);
	ts_sha256_update(&sc, tbs, (size_t)(c.p - tbs));
	ts_sha256_out(&sc, hash);
	chk(ts_der_tlv(&c, 0x30, &val, &len), "signature algorithm");
	chk(ts_der_tlv(&c, 0x03, &bits, &len) && len > 1 && bits[0] == 0,
		"signatureValue");
	chk(br_ecdsa_i31_vrfy_asn1(&br_ec_prime_i31, hash, 32, &pk.key.ec,
		bits + 1, len - 1), "the certificate signature verifies");

	/* PEM roundtrip, the label is checked */
	n = ts_pem_encode("CERTIFICATE", cert, clen, pem);
	chk(n > 0, "PEM encode");
	n = ts_pem_decode(pem, n, "CERTIFICATE", back, sizeof back);
	chk(n == clen && memcmp(cert, back, clen) == 0, "PEM roundtrip");
	chk(ts_pem_decode(pem, strlen(pem), "PRIVATE KEY", back,
		sizeof back) == 0, "the PEM label is checked");

	n = ts_pem_encode("PRIVATE KEY", key, klen, pem);
	chk(n > 0, "key PEM encode");
	n = ts_pem_decode(pem, n, "PRIVATE KEY", back, sizeof back);
	chk(n == klen && memcmp(key, back, klen) == 0, "key PEM roundtrip");
}

/* ---- golden session replay ---- */

static void
session_check(const char *name, const unsigned char *server, size_t slen,
	const unsigned char *client, size_t clen)
{
	struct mock m;
	struct ts_conn *t;
	unsigned char buf[256];
	int r, total;

	memset(&m, 0, sizeof m);
	m.in = server;
	m.in_len = slen;
	m.eof = 1;
	rng_reset();
	t = ts_new("localhost", &m, mock_read, mock_write);
	if (t == NULL) {
		chk(0, name);
		return;
	}
	for (;;) {
		r = ts_handshake(t);
		if (r == TS_OK) {
			break;
		}
		if (r == TS_WANT_READ || r == TS_WANT_WRITE) {
			printf("       %s: stuck (%s)\n", name,
				ts_strerror(r));
			chk(0, name);
			ts_free(t);
			return;
		}
		printf("       %s: handshake error %s\n", name,
			ts_strerror(r));
		chk(0, name);
		ts_free(t);
		return;
	}
	chk(ts_error(t) == TS_OK, name);
	chk(ts_write(t, "rein\n", 5) == 5, name);
	chk(m.out_len == clen && memcmp(m.out, client, clen) == 0,
		name);
	total = 0;
	for (;;) {
		r = ts_read(t, buf + total, sizeof buf - (size_t)total);
		if (r > 0) {
			total += r;
			continue;
		}
		break;
	}
	chk(total == 5 && memcmp(buf, "nier\n", 5) == 0, name);
	/* the captured server closed the socket without close_notify */
	chk(r == TS_ERR_IO, name);
	ts_free(t);
}

static void
test_sessions(void)
{
	printf("# session ecdhe_rsa\n");
	session_check("ecdhe_rsa",
		ts_session_server, sizeof ts_session_server,
		ts_session_client, sizeof ts_session_client);
	printf("# session rsa\n");
	session_check("rsa",
		ts_session_rsa_server, sizeof ts_session_rsa_server,
		ts_session_rsa_client, sizeof ts_session_rsa_client);
	printf("# session ecdhe_ecdsa\n");
	session_check("ecdhe_ecdsa",
		ts_session_ec_server, sizeof ts_session_ec_server,
		ts_session_ec_client, sizeof ts_session_ec_client);
}

int
main(void)
{
	test_sha256();
	test_hmac_prf();
	test_aes_gcm();
	test_records();
	test_x509();
	test_api();
	test_limits();
	test_ec_sign();
	test_ec_key();
	test_ec_cert();
	test_sessions();
	printf("%d checks, %d failures\n", checks, failures);
	return failures != 0;
}
