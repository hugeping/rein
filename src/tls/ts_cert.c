/*
 * Client keys and certificates for TinyTLS: P-256 ECDSA key
 * generation, ECDSA signing over SHA-256 and a self-signed X.509
 * certificate builder, all in DER.  A client certificate is an
 * identity the user chooses, so nothing here validates anything:
 * the server is free to accept or reject it.
 *
 * Only P-256 is supported, as everywhere else in the client.
 */

#include <string.h>
#include <time.h>

#include "ts_priv.h"
#include "inner.h"

#define FIELD_LEN  32
#define POINT_LEN  65
#define I31_LEN    10        /* 256 bits in 31-bit words plus the count */

/* ---- DER cursor (also used by ts_x509.c) ---- */

int
ts_der_tlv(ts_der *c, unsigned tag, const unsigned char **val, size_t *len)
{
	size_t l;
	unsigned t, n, u;

	if ((size_t)(c->end - c->p) < 2) {
		return 0;
	}
	t = *c->p ++;
	if (t != tag) {
		return 0;
	}
	l = *c->p ++;
	if (l & 0x80) {
		n = (unsigned)(l & 0x7F);
		if (n == 0 || n > sizeof(size_t)
			|| (size_t)(c->end - c->p) < n)
		{
			return 0;
		}
		l = 0;
		for (u = 0; u < n; u ++) {
			l = (l << 8) | *c->p ++;
		}
	}
	if ((size_t)(c->end - c->p) < l) {
		return 0;
	}
	*val = c->p;
	*len = l;
	c->p += l;
	return 1;
}

int
ts_der_enter(ts_der *c, unsigned tag)
{
	const unsigned char *val;
	size_t len;

	if (!ts_der_tlv(c, tag, &val, &len)) {
		return 0;
	}
	c->p = val;
	c->end = val + len;
	return 1;
}

/* ---- the key ---- */

static const unsigned char oid_ec_pubkey[] = {
	0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01
};

static const unsigned char oid_p256[] = {
	0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07
};

/*
 * Decode the scalar d into dd and fill n and n0i with the order and
 * its Montgomery constant.  When pub is not NULL, also compute the
 * public point.  Return 0 when the key is zero or out of range.
 */
static int
ec_scalar(const unsigned char *d, unsigned char *pub,
	uint32_t *dd, uint32_t *n, uint32_t *n0i)
{
	const unsigned char *order;
	size_t olen;

	order = br_ec_prime_i31.order(BR_EC_secp256r1, &olen);
	if (order == NULL || olen != FIELD_LEN) {
		return 0;
	}
	br_i31_decode(n, order, olen);
	*n0i = br_i31_ninv31(n[1]);
	if (!br_i31_decode_mod(dd, d, FIELD_LEN, n) || br_i31_iszero(dd)) {
		return 0;
	}
	if (pub != NULL) {
		size_t plen = br_ec_prime_i31.mulgen(pub, d, FIELD_LEN,
			BR_EC_secp256r1);

		if (plen != POINT_LEN) {
			return 0;
		}
	}
	return 1;
}

/* generate a key; d is the 32-byte scalar, pub the 65-byte point */
int
ts_ec_keygen(unsigned char *d, unsigned char *pub)
{
	uint32_t n[I31_LEN], dd[I31_LEN];
	uint32_t n0i;

	for (;;) {
		ts_random(d, FIELD_LEN);
		if (ec_scalar(d, pub, dd, n, &n0i)) {
			return 1;
		}
	}
}

static size_t
der_len(unsigned char *p, size_t len)
{
	if (len < 0x80) {
		p[0] = (unsigned char)len;
		return 1;
	}
	if (len < 0x100) {
		p[0] = 0x81;
		p[1] = (unsigned char)len;
		return 2;
	}
	p[0] = 0x82;
	p[1] = (unsigned char)(len >> 8);
	p[2] = (unsigned char)len;
	return 3;
}

static size_t
der_tlv(unsigned char *out, unsigned tag, const unsigned char *val,
	size_t len)
{
	size_t h = der_len(out + 1, len);

	out[0] = (unsigned char)tag;
	if (len > 0) {
		memcpy(out + 1 + h, val, len);
	}
	return 1 + h + len;
}

static size_t
der_int(unsigned char *out, const unsigned char *val, size_t len)
{
	size_t z = 0;

	while (z + 1 < len && val[z] == 0) {
		z ++;
	}
	if (val[z] & 0x80) {
		out[0] = 0x02;
		out[1] = (unsigned char)(len - z + 1);
		out[2] = 0x00;
		memcpy(out + 3, val + z, len - z);
		return len - z + 3;
	}
	out[0] = 0x02;
	out[1] = (unsigned char)(len - z);
	memcpy(out + 2, val + z, len - z);
	return len - z + 2;
}

static size_t
der_sig(unsigned char *sig, const unsigned char *r, const unsigned char *s)
{
	unsigned char body[80];
	size_t bl = 0;

	bl += der_int(body + bl, r, FIELD_LEN);
	bl += der_int(body + bl, s, FIELD_LEN);
	return der_tlv(sig, 0x30, body, bl);
}

/*
 * Sign a 32-byte hash (SHA-256) with a P-256 key and return the DER
 * ECDSA signature, as TLS wants it; sig must have room for 80 bytes.
 */
int
ts_ec_sign(const unsigned char *d, const unsigned char *hash,
	unsigned char *sig, size_t *siglen)
{
	uint32_t n[I31_LEN], dd[I31_LEN], k[I31_LEN], r[I31_LEN],
		s[I31_LEN], t1[I31_LEN], t2[I31_LEN], t3[I31_LEN];
	unsigned char kb[FIELD_LEN], point[POINT_LEN], rb[FIELD_LEN],
		sb[FIELD_LEN], e[FIELD_LEN];
	const unsigned char *order;
	size_t olen;
	uint32_t n0i, cc;
	int try;

	if (!ec_scalar(d, NULL, dd, n, &n0i)) {
		return 0;
	}
	order = br_ec_prime_i31.order(BR_EC_secp256r1, &olen);
	memcpy(e, order, olen);
	e[olen - 1] -= 2;       /* the exponent of the inverse: n - 2 */
	for (try = 0; try < 64; try ++) {
		ts_random(kb, FIELD_LEN);
		if (!br_i31_decode_mod(k, kb, FIELD_LEN, n)
			|| br_i31_iszero(k))
		{
			continue;
		}
		if (br_ec_prime_i31.mulgen(point, kb, FIELD_LEN,
			BR_EC_secp256r1) != POINT_LEN)
		{
			continue;
		}

		/* r = x(k*G) mod n */
		br_i31_zero(r, n[0]);
		br_i31_decode(r, point + 1, FIELD_LEN);
		r[0] = n[0];
		br_i31_sub(r, n, br_i31_sub(r, n, 0) ^ 1);
		if (br_i31_iszero(r)) {
			continue;
		}

		/* t1 = h mod n, in Montgomery form */
		br_ecdsa_i31_bits2int(t1, hash, 32, n[0]);
		br_i31_sub(t1, n, br_i31_sub(t1, n, 0) ^ 1);
		br_i31_to_monty(t1, n);

		/* t3 = r*d, in Montgomery form */
		memcpy(t2, dd, sizeof t2);
		br_i31_to_monty(t2, n);
		memcpy(t3, r, sizeof t3);
		br_i31_to_monty(t3, n);
		br_i31_montymul(s, t3, t2, n, n0i);

		/* t1 = h + r*d, still in Montgomery form */
		cc = br_i31_add(t1, s, 1);
		br_i31_sub(t1, n, cc | (br_i31_sub(t1, n, 0) ^ 1));

		/* s = (h + r*d)/k */
		br_i31_modpow(k, e, FIELD_LEN, n, n0i, t2, t3);
		br_i31_to_monty(k, n);
		br_i31_montymul(s, k, t1, n, n0i);
		br_i31_from_monty(s, n, n0i);
		if (br_i31_iszero(s)) {
			continue;
		}

		br_i31_encode(rb, FIELD_LEN, r);
		br_i31_encode(sb, FIELD_LEN, s);
		*siglen = der_sig(sig, rb, sb);
		return 1;
	}
	return 0;
}

/*
 * Parse a private key in DER: the SEC1 ECPrivateKey or the PKCS#8
 * PrivateKeyInfo with the P-256 curve.  Return the 32-byte scalar.
 */
int
ts_ec_key_parse(const unsigned char *der, size_t len, unsigned char *d)
{
	ts_der c, key;
	const unsigned char *val;
	size_t vlen;
	unsigned char dd[FIELD_LEN], pub[POINT_LEN];
	uint32_t n[I31_LEN], k[I31_LEN];
	uint32_t n0i;

	c.p = der;
	c.end = der + len;
	if (!ts_der_enter(&c, 0x30)
		|| !ts_der_tlv(&c, 0x02, &val, &vlen))
	{
		return 0;
	}
	if (vlen == 1 && val[0] == 0) {
		/* PKCS#8: the algorithm, then the SEC1 key inside */
		ts_der alg;

		if (!ts_der_tlv(&c, 0x30, &val, &vlen)) {
			return 0;
		}
		alg.p = val;
		alg.end = val + vlen;
		if (!ts_der_tlv(&alg, 0x06, &val, &vlen)
			|| vlen != sizeof oid_ec_pubkey
			|| memcmp(val, oid_ec_pubkey, vlen) != 0)
		{
			return 0;
		}
		if (!ts_der_tlv(&alg, 0x06, &val, &vlen)
			|| vlen != sizeof oid_p256
			|| memcmp(val, oid_p256, vlen) != 0)
		{
			return 0;
		}
		if (!ts_der_tlv(&c, 0x04, &val, &vlen)) {
			return 0;
		}
		key.p = val;
		key.end = val + vlen;
		if (!ts_der_enter(&key, 0x30)
			|| !ts_der_tlv(&key, 0x02, &val, &vlen)
			|| vlen != 1 || val[0] != 1)
		{
			return 0;
		}
	} else if (vlen == 1 && val[0] == 1) {
		/* SEC1 ECPrivateKey */
		key = c;
	} else {
		return 0;
	}
	if (!ts_der_tlv(&key, 0x04, &val, &vlen)
		|| vlen < 1 || vlen > FIELD_LEN)
	{
		return 0;
	}
	memset(dd, 0, FIELD_LEN);
	memcpy(dd + FIELD_LEN - vlen, val, vlen);
	if (!ec_scalar(dd, pub, k, n, &n0i)) {
		return 0;
	}
	memcpy(d, dd, FIELD_LEN);
	return 1;
}

/* the PKCS#8 PrivateKeyInfo of a P-256 key, 79 bytes */
static size_t
ec_key_der(unsigned char *out, const unsigned char *d)
{
	unsigned char alg[24], sec1[64], sec1s[80], body[128], oid[16];
	size_t an = 0, an2 = 0, sn = 0, bn = 0;

	an += der_tlv(alg + an, 0x06, oid_ec_pubkey, sizeof oid_ec_pubkey);
	an += der_tlv(alg + an, 0x06, oid_p256, sizeof oid_p256);

	an2 += der_tlv(oid + an2, 0x06, oid_p256, sizeof oid_p256);

	sn += der_tlv(sec1 + sn, 0x02, (const unsigned char *)"\x01", 1);
	sn += der_tlv(sec1 + sn, 0x04, d, FIELD_LEN);
	sn += der_tlv(sec1 + sn, 0xA0, oid, an2);
	sn = der_tlv(sec1s, 0x30, sec1, sn);

	bn += der_tlv(body + bn, 0x02, (const unsigned char *)"\x00", 1);
	bn += der_tlv(body + bn, 0x30, alg, an);
	bn += der_tlv(body + bn, 0x04, sec1s, sn);
	return der_tlv(out, 0x30, body, bn);
}

/* ---- the self-signed certificate ---- */

static const unsigned char oid_cn[] = { 0x55, 0x04, 0x03 };
static const unsigned char oid_sig[] = {
	0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02
};

static void
put2(char *p, int v)
{
	p[0] = (char)('0' + v / 10);
	p[1] = (char)('0' + v % 10);
}

static size_t
time_der(unsigned char *out, time_t when)
{
	struct tm *tm = gmtime(&when);
	char s[16];
	int y;

	if (tm->tm_year >= 100 && tm->tm_year < 150) {
		put2(s, tm->tm_year - 100);
		put2(s + 2, tm->tm_mon + 1);
		put2(s + 4, tm->tm_mday);
		put2(s + 6, tm->tm_hour);
		put2(s + 8, tm->tm_min);
		put2(s + 10, tm->tm_sec);
		s[12] = 'Z';
		return der_tlv(out, 0x17, (const unsigned char *)s, 13);
	}
	y = tm->tm_year + 1900;
	s[0] = (char)('0' + y / 1000);
	s[1] = (char)('0' + (y / 100) % 10);
	put2(s + 2, y % 100);
	put2(s + 4, tm->tm_mon + 1);
	put2(s + 6, tm->tm_mday);
	put2(s + 8, tm->tm_hour);
	put2(s + 10, tm->tm_min);
	put2(s + 12, tm->tm_sec);
	s[14] = 'Z';
	return der_tlv(out, 0x18, (const unsigned char *)s, 15);
}

static size_t
build_name(unsigned char *out, const char *cn)
{
	unsigned char val[128], seq[136], set[144];
	size_t cl = strlen(cn), n = 0, l;

	if (cl > 64) {
		cl = 64;
	}
	n += der_tlv(val + n, 0x06, oid_cn, sizeof oid_cn);
	n += der_tlv(val + n, 0x0C, (const unsigned char *)cn, cl);
	l = der_tlv(seq, 0x30, val, n);
	l = der_tlv(set, 0x31, seq, l);
	return der_tlv(out, 0x30, set, l);
}

static size_t
build_spki(unsigned char *out, const unsigned char *q)
{
	unsigned char alg[24], body[128], bits[POINT_LEN + 1];
	size_t an = 0, bn = 0;

	an += der_tlv(alg + an, 0x06, oid_ec_pubkey, sizeof oid_ec_pubkey);
	an += der_tlv(alg + an, 0x06, oid_p256, sizeof oid_p256);

	bn += der_tlv(body + bn, 0x30, alg, an);
	bits[0] = 0x00;
	memcpy(bits + 1, q, POINT_LEN);
	bn += der_tlv(body + bn, 0x03, bits, sizeof bits);
	return der_tlv(out, 0x30, body, bn);
}

/*
 * Make a self-signed P-256 certificate with the given common name and
 * return it (DER) together with the PKCS#8 key (DER).  cert must have
 * room for 1024 bytes, key for 128.
 */
int
ts_ec_selfsign(const char *cn, unsigned char *cert, size_t *certlen,
	unsigned char *key, size_t *keylen)
{
	unsigned char d[FIELD_LEN], q[POINT_LEN], hash[32], sig[80];
	unsigned char serial[8], oid[16], sigalg[24], name[160], valid[64];
	unsigned char spki[160], body[768], tbs[768], full[896];
	unsigned char bits[80];
	size_t bl = 0, n, sigalg_len, tbs_len, sigl;
	ts_sha256_ctx sc;
	time_t now;
	int i;

	if (cn == NULL || cn[0] == '\0') {
		cn = "rein";
	}
	if (!ts_ec_keygen(d, q)) {
		return 0;
	}

	ts_random(serial, sizeof serial);
	serial[0] &= 0x7F;
	for (i = 0; i < (int)sizeof serial; i ++) {
		if (serial[i] != 0) {
			break;
		}
	}
	if (i == (int)sizeof serial) {
		serial[0] = 1;
	}

	n = der_tlv(oid, 0x06, oid_sig, sizeof oid_sig);
	sigalg_len = der_tlv(sigalg, 0x30, oid, n);

	{
		unsigned char ver[3] = { 0x02, 0x01, 0x02 };
		unsigned char v[64];
		size_t vn = 0;

		bl += der_tlv(body + bl, 0xA0, ver, sizeof ver);
		bl += der_tlv(body + bl, 0x02, serial, sizeof serial);
		memcpy(body + bl, sigalg, sigalg_len);
		bl += sigalg_len;

		n = build_name(name, cn);
		memcpy(body + bl, name, n);
		bl += n;

		now = time(NULL);
		vn += time_der(v + vn, now - 86400);
		vn += time_der(v + vn, now + (time_t)10 * 365 * 86400);
		vn = der_tlv(valid, 0x30, v, vn);
		memcpy(body + bl, valid, vn);
		bl += vn;

		memcpy(body + bl, name, n);        /* subject = issuer */
		bl += n;

		n = build_spki(spki, q);
		memcpy(body + bl, spki, n);
		bl += n;
	}
	tbs_len = der_tlv(tbs, 0x30, body, bl);

	ts_sha256_init(&sc);
	ts_sha256_update(&sc, tbs, tbs_len);
	ts_sha256_out(&sc, hash);
	if (!ts_ec_sign(d, hash, sig, &sigl) || sigl > sizeof sig - 1) {
		return 0;
	}

	bl = 0;
	memcpy(full + bl, tbs, tbs_len);
	bl += tbs_len;
	memcpy(full + bl, sigalg, sigalg_len);
	bl += sigalg_len;
	bits[0] = 0x00;
	memcpy(bits + 1, sig, sigl);
	bl += der_tlv(full + bl, 0x03, bits, sigl + 1);
	*certlen = der_tlv(cert, 0x30, full, bl);
	*keylen = ec_key_der(key, d);
	return 1;
}
