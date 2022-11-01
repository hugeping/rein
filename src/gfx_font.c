/*
 * Copyright 2021 Peter Kosyh <p.kosyh at gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 */

/* binding to libschrift library by Peter Kosyh */
/* see LICENSE file for libschrift license */

#include "external.h"
#include "gfx.h"
#include "utf.h"
#include "schrift.h"

struct _font_t {
	SFT sft;
	void *data;
	float size;
	int height;
};

int
font_height(font_t *font)
{
	return font->height;
}

int
sft_floor(double v)
{
	return (v<0)?ceil(v):floor(v);
}

int
font_width(font_t *font, const char *text)
{
	int x = 0;
	struct SFT_GMetrics metrics;
	SFT_Glyph glyph, oglyph = 0;
	SFT_Kerning kern;
	const char *p = text;
	unsigned codepoint;
	int xend = 0;
	while (*p) {
		p = utf8_to_codepoint(p, &codepoint);
		sft_lookup(&font->sft, codepoint, &glyph);
		kern.xShift = 0;
		if (oglyph)
			sft_kerning(&font->sft, oglyph, glyph,  &kern);
		oglyph = glyph;
		sft_gmetrics(&font->sft, glyph, &metrics);
		x += sft_floor(kern.xShift);
		if (x < 0)
			x = 0;
		if (x + sft_floor(metrics.leftSideBearing) < 0)
			x += -sft_floor(metrics.leftSideBearing);
		xend = x + sft_floor(metrics.leftSideBearing) +
			((metrics.minWidth > metrics.advanceWidth)?metrics.minWidth:round(metrics.advanceWidth));
		x += round(metrics.advanceWidth);
	}
	return xend;
}

font_t*
font_load(const char *filename, float size)
{
	font_t *font = NULL;
	struct SFT_LMetrics metrics;

	FILE *fp = NULL;
	long fsize;
	font = malloc(sizeof(font_t));
	if (!font)
		goto err;
	memset(font, 0, sizeof(font_t));
	font->size = size;
	fp = fopen(filename, "rb");
	if (!fp)
		goto err;
	if (fseek(fp, 0, SEEK_END) < 0)
		goto err;
	fsize = ftell(fp);
	if (fsize < 0)
		goto err;
	if (fseek(fp, 0, SEEK_SET) < 0)
		goto err;
	font->data = malloc(fsize);
	if (!font->data)
		goto err;
	if (fread(font->data, 1, fsize, fp) != fsize)
		goto err;
	fclose(fp); fp = NULL;

	font->size = size;
	font->sft.xScale = size;
	font->sft.yScale = size;
	font->sft.font = sft_loadmem(font->data, fsize);
	font->sft.flags = SFT_DOWNWARD_Y;
	if (!font->sft.font)
		goto err;
	sft_lmetrics(&font->sft, &metrics);
	font->height = metrics.ascender - metrics.descender + metrics.lineGap;
	return font;
err:
	if (font && font->data)
		free(font->data);
	free(font);
	return NULL;
}

int
font_render(font_t *font, const char *text, img_t *img)
{
	int x = 0, y, xx, i, pos, yoff, xoff;
	static char pixels[256*256];
	SFT_Image g = {
		.width  = 256,
		.height = 256,
		.pixels = pixels,
	};
	SFT_Glyph glyph, oglyph = 0;
	struct SFT_LMetrics lm;
	struct SFT_GMetrics metrics;
	SFT_Kerning kern;
	const char *p = text;
	unsigned codepoint;
	sft_lmetrics(&font->sft, &lm);
	while (*p) {
		p = utf8_to_codepoint(p, &codepoint);
		sft_lookup(&font->sft, codepoint, &glyph);
		kern.xShift = 0;
		if (oglyph)
			sft_kerning(&font->sft, oglyph, glyph,  &kern);
		oglyph = glyph;
		x += sft_floor(kern.xShift);
		if (x < 0)
			x = 0;
		sft_gmetrics(&font->sft, glyph, &metrics);
		g.width = metrics.minWidth;
		g.height = metrics.minHeight;
		sft_render(&font->sft, glyph, g);
		i = 0;
		yoff = floor(lm.ascender + metrics.yOffset);
		xoff = sft_floor(metrics.leftSideBearing);
		if (x + xoff < 0)
			x += -xoff;
		for (y = 0; y < g.height; y++) {
			if (yoff + y >= img->h)
				break;
			pos = ((y + yoff)* img->w + x + xoff) * 4;
			for (xx = 0; xx < g.width; xx++) {
				if (xx + x + xoff>= img->w) {
					i += g.width - xx;
					break;
				}
				if (pixels[i]) {
					pos += 3;
					img->ptr[pos++] = pixels[i];
				} else
					pos += 4;
				i ++;
			}
		}
		x += round(metrics.advanceWidth);
	}
	return 0;
}

void
font_free(font_t *font)
{
	sft_freefont(font->sft.font);
	free(font->data);
	free(font);
}

static const char *info = "libschrift";
const char *
font_renderer()
{
	return info;
}
