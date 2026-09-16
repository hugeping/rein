/*
 * Extract the public key from a DER certificate. Nothing is
 * validated here, only the SubjectPublicKeyInfo is decoded: RSA
 * keys (modulus and exponent) and P-256 EC keys.
 */

#include <string.h>

#include "ts_priv.h"

typedef struct {
	const unsigned char *p;
	const unsigned char *end;
} der_cursor;

static int
der_tlv(der_cursor *c, unsigned tag, const unsigned char **val, size_t *len)
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

static int
der_enter(der_cursor *c, unsigned tag)
{
	const unsigned char *val;
	size_t len;

	if (!der_tlv(c, tag, &val, &len)) {
		return 0;
	}
	c->p = val;
	c->end = val + len;
	return 1;
}

int
ts_x509_get_pkey(const unsigned char *cert, size_t clen, ts_pkey *pk)
{
	static const unsigned char oid_rsa[] = {
		0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01
	};
	static const unsigned char oid_ec[] = {
		0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01
	};
	static const unsigned char oid_p256[] = {
		0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07
	};
	der_cursor c, alg, spki;
	const unsigned char *val, *oid, *bits;
	size_t len, oid_len, bits_len;
	unsigned u;

	c.p = cert;
	c.end = cert + clen;
	if (!der_enter(&c, 0x30)) {                    /* Certificate */
		return 0;
	}
	if (!der_enter(&c, 0x30)) {                    /* tbsCertificate */
		return 0;
	}
	if ((size_t)(c.end - c.p) >= 2 && *c.p == 0xA0) {
		if (!der_tlv(&c, 0xA0, &val, &len)) {  /* version */
			return 0;
		}
	}
	if (!der_tlv(&c, 0x02, &val, &len)) {          /* serialNumber */
		return 0;
	}
	for (u = 0; u < 4; u ++) {
		/* signature, issuer, validity, subject */
		if (!der_tlv(&c, 0x30, &val, &len)) {
			return 0;
		}
	}
	if (!der_tlv(&c, 0x30, &val, &len)) {          /* SPKI */
		return 0;
	}
	spki.p = val;
	spki.end = val + len;
	if (!der_tlv(&spki, 0x30, &val, &len)) {       /* AlgorithmIdentifier */
		return 0;
	}
	alg.p = val;
	alg.end = val + len;
	if (!der_tlv(&alg, 0x06, &oid, &oid_len)) {    /* key algorithm */
		return 0;
	}
	if (!der_tlv(&spki, 0x03, &bits, &bits_len)) { /* BIT STRING */
		return 0;
	}
	if (bits_len < 1 || *bits != 0) {
		return 0;
	}
	bits ++;
	bits_len --;
	if (oid_len == sizeof oid_rsa && memcmp(oid, oid_rsa, oid_len) == 0) {
		der_cursor rc;

		rc.p = bits;
		rc.end = bits + bits_len;
		if (!der_enter(&rc, 0x30)) {           /* RSAPublicKey */
			return 0;
		}
		if (!der_tlv(&rc, 0x02, &val, &len)) { /* n */
			return 0;
		}
		pk->key.rsa.n = (unsigned char *)val;
		pk->key.rsa.nlen = len;
		if (!der_tlv(&rc, 0x02, &val, &len)) { /* e */
			return 0;
		}
		pk->key.rsa.e = (unsigned char *)val;
		pk->key.rsa.elen = len;
		pk->key_type = TS_KEY_RSA;
		return 1;
	}
	if (oid_len == sizeof oid_ec && memcmp(oid, oid_ec, oid_len) == 0) {
		if (!der_tlv(&alg, 0x06, &val, &len)) { /* namedCurve */
			return 0;
		}
		if (len != sizeof oid_p256 || memcmp(val, oid_p256, len) != 0) {
			return 0;
		}
		pk->key.ec.curve = BR_EC_secp256r1;
		pk->key.ec.q = (unsigned char *)bits;
		pk->key.ec.qlen = bits_len;
		pk->key_type = TS_KEY_EC;
		return 1;
	}
	return 0;
}
