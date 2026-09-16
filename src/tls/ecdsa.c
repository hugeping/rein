/*
 * Copyright (c) 2016 Thomas Pornin <pornin@bolet.org>
 *
 * Permission is hereby granted, free of charge, to any person obtaining 
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be 
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "inner.h"

/* ==== ecdsa_atr ==== */

/* see bearssl_ec.h */
size_t
br_ecdsa_asn1_to_raw(void *sig, size_t sig_len)
{
	/*
	 * Note: this code is a bit lenient in that it accepts a few
	 * deviations to DER with regards to minimality of encoding of
	 * lengths and integer values. These deviations are still
	 * unambiguous.
	 *
	 * Signature format is a SEQUENCE of two INTEGER values. We
	 * support only integers of less than 127 bytes each (signed
	 * encoding) so the resulting raw signature will have length
	 * at most 254 bytes.
	 */

	unsigned char *buf, *r, *s;
	size_t zlen, rlen, slen, off;
	unsigned char tmp[254];

	buf = sig;
	if (sig_len < 8) {
		return 0;
	}

	/*
	 * First byte is SEQUENCE tag.
	 */
	if (buf[0] != 0x30) {
		return 0;
	}

	/*
	 * The SEQUENCE length will be encoded over one or two bytes. We
	 * limit the total SEQUENCE contents to 255 bytes, because it
	 * makes things simpler; this is enough for subgroup orders up
	 * to 999 bits.
	 */
	zlen = buf[1];
	if (zlen > 0x80) {
		if (zlen != 0x81) {
			return 0;
		}
		zlen = buf[2];
		if (zlen != sig_len - 3) {
			return 0;
		}
		off = 3;
	} else {
		if (zlen != sig_len - 2) {
			return 0;
		}
		off = 2;
	}

	/*
	 * First INTEGER (r).
	 */
	if (buf[off ++] != 0x02) {
		return 0;
	}
	rlen = buf[off ++];
	if (rlen >= 0x80) {
		return 0;
	}
	r = buf + off;
	off += rlen;

	/*
	 * Second INTEGER (s).
	 */
	if (off + 2 > sig_len) {
		return 0;
	}
	if (buf[off ++] != 0x02) {
		return 0;
	}
	slen = buf[off ++];
	if (slen >= 0x80 || slen != sig_len - off) {
		return 0;
	}
	s = buf + off;

	/*
	 * Removing leading zeros from r and s.
	 */
	while (rlen > 0 && *r == 0) {
		rlen --;
		r ++;
	}
	while (slen > 0 && *s == 0) {
		slen --;
		s ++;
	}

	/*
	 * Compute common length for the two integers, then copy integers
	 * into the temporary buffer, and finally copy it back over the
	 * signature buffer.
	 */
	zlen = rlen > slen ? rlen : slen;
	sig_len = zlen << 1;
	memset(tmp, 0, sig_len);
	memcpy(tmp + zlen - rlen, r, rlen);
	memcpy(tmp + sig_len - slen, s, slen);
	memcpy(sig, tmp, sig_len);
	return sig_len;
}


/* ==== ecdsa_i31_bits ==== */

/* see inner.h */
void
br_ecdsa_i31_bits2int(uint32_t *x,
	const void *src, size_t len, uint32_t ebitlen)
{
	uint32_t bitlen, hbitlen;
	int sc;

	bitlen = ebitlen - (ebitlen >> 5);
	hbitlen = (uint32_t)len << 3;
	if (hbitlen > bitlen) {
		len = (bitlen + 7) >> 3;
		sc = (int)((hbitlen - bitlen) & 7);
	} else {
		sc = 0;
	}
	br_i31_zero(x, ebitlen);
	br_i31_decode(x, src, len);
	br_i31_rshift(x, sc);
	x[0] = ebitlen;
}


/* ==== ecdsa_i31_vrfy_asn1 ==== */

#define FIELD_LEN   ((BR_MAX_EC_SIZE + 7) >> 3)

/* see bearssl_ec.h */
uint32_t
br_ecdsa_i31_vrfy_asn1(const br_ec_impl *impl,
	const void *hash, size_t hash_len,
	const br_ec_public_key *pk,
	const void *sig, size_t sig_len)
{
	/*
	 * We use a double-sized buffer because a malformed ASN.1 signature
	 * may trigger a size expansion when converting to "raw" format.
	 */
	unsigned char rsig[(FIELD_LEN << 2) + 24];

	if (sig_len > ((sizeof rsig) >> 1)) {
		return 0;
	}
	memcpy(rsig, sig, sig_len);
	sig_len = br_ecdsa_asn1_to_raw(rsig, sig_len);
	return br_ecdsa_i31_vrfy_raw(impl, hash, hash_len, pk, rsig, sig_len);
}


/* ==== ecdsa_i31_vrfy_raw ==== */

#define I31_LEN     ((BR_MAX_EC_SIZE + 61) / 31)
#define POINT_LEN   (1 + (((BR_MAX_EC_SIZE + 7) >> 3) << 1))

/* see bearssl_ec.h */
uint32_t
br_ecdsa_i31_vrfy_raw(const br_ec_impl *impl,
	const void *hash, size_t hash_len,
	const br_ec_public_key *pk,
	const void *sig, size_t sig_len)
{
	/*
	 * IMPORTANT: this code is fit only for curves with a prime
	 * order. This is needed so that modular reduction of the X
	 * coordinate of a point can be done with a simple subtraction.
	 */
	const br_ec_curve_def *cd;
	uint32_t n[I31_LEN], r[I31_LEN], s[I31_LEN], t1[I31_LEN], t2[I31_LEN];
	unsigned char tx[(BR_MAX_EC_SIZE + 7) >> 3];
	unsigned char ty[(BR_MAX_EC_SIZE + 7) >> 3];
	unsigned char eU[POINT_LEN];
	size_t nlen, rlen, ulen;
	uint32_t n0i, res;

	/*
	 * If the curve is not supported, then report an error.
	 */
	if (((impl->supported_curves >> pk->curve) & 1) == 0) {
		return 0;
	}

	/*
	 * Get the curve parameters (generator and order).
	 */
	switch (pk->curve) {
	case BR_EC_secp256r1: /* pruned: only P-256 */
		cd = &br_secp256r1;
		break;
	default:
		return 0;
	}

	/*
	 * Signature length must be even.
	 */
	if (sig_len & 1) {
		return 0;
	}
	rlen = sig_len >> 1;

	/*
	 * Public key point must have the proper size for this curve.
	 */
	if (pk->qlen != cd->generator_len) {
		return 0;
	}

	/*
	 * Get modulus; then decode the r and s values. They must be
	 * lower than the modulus, and s must not be null.
	 */
	nlen = cd->order_len;
	br_i31_decode(n, cd->order, nlen);
	n0i = br_i31_ninv31(n[1]);
	if (!br_i31_decode_mod(r, sig, rlen, n)) {
		return 0;
	}
	if (!br_i31_decode_mod(s, (const unsigned char *)sig + rlen, rlen, n)) {
		return 0;
	}
	if (br_i31_iszero(s)) {
		return 0;
	}

	/*
	 * Invert s. We do that with a modular exponentiation; we use
	 * the fact that for all the curves we support, the least
	 * significant byte is not 0 or 1, so we can subtract 2 without
	 * any carry to process.
	 * We also want 1/s in Montgomery representation, which can be
	 * done by converting _from_ Montgomery representation before
	 * the inversion (because (1/s)*R = 1/(s/R)).
	 */
	br_i31_from_monty(s, n, n0i);
	memcpy(tx, cd->order, nlen);
	tx[nlen - 1] -= 2;
	br_i31_modpow(s, tx, nlen, n, n0i, t1, t2);

	/*
	 * Truncate the hash to the modulus length (in bits) and reduce
	 * it modulo the curve order. The modular reduction can be done
	 * with a subtraction since the truncation already reduced the
	 * value to the modulus bit length.
	 */
	br_ecdsa_i31_bits2int(t1, hash, hash_len, n[0]);
	br_i31_sub(t1, n, br_i31_sub(t1, n, 0) ^ 1);

	/*
	 * Multiply the (truncated, reduced) hash value with 1/s, result in
	 * t2, encoded in ty.
	 */
	br_i31_montymul(t2, t1, s, n, n0i);
	br_i31_encode(ty, nlen, t2);

	/*
	 * Multiply r with 1/s, result in t1, encoded in tx.
	 */
	br_i31_montymul(t1, r, s, n, n0i);
	br_i31_encode(tx, nlen, t1);

	/*
	 * Compute the point x*Q + y*G.
	 */
	ulen = cd->generator_len;
	memcpy(eU, pk->q, ulen);
	res = impl->muladd(eU, NULL, ulen,
		tx, nlen, ty, nlen, cd->curve);

	/*
	 * Get the X coordinate, reduce modulo the curve order, and
	 * compare with the 'r' value.
	 *
	 * The modular reduction can be done with subtractions because
	 * we work with curves of prime order, so the curve order is
	 * close to the field order (Hasse's theorem).
	 */
	br_i31_zero(t1, n[0]);
	br_i31_decode(t1, &eU[1], ulen >> 1);
	t1[0] = n[0];
	br_i31_sub(t1, n, br_i31_sub(t1, n, 0) ^ 1);
	res &= ~br_i31_sub(t1, r, 1);
	res &= br_i31_iszero(t1);
	return res;
}

