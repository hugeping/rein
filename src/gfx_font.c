#include "external.h"
#include "stb_truetype.h"
#include "gfx.h"

#define MAX_GLYPHSET 256

typedef struct {
	img_t *image;
	stbtt_bakedchar glyphs[256];
} glyphset_t;

struct _font_t {
	void *data;
	stbtt_fontinfo stbfont;
	glyphset_t *sets[MAX_GLYPHSET];
	float size;
	int height;
};

static glyphset_t*
load_glyphset(font_t *font, int idx)
{
	unsigned char col[4] = { 255, 255, 255, 255 };
	int w = 128, h = 128, i;
	float s;
	int ascent, descent, linegap;
	int res;
	unsigned char c;
	glyphset_t *set = calloc(1, sizeof(glyphset_t));
retry:
	set->image = img_new(w, h);
	s = stbtt_ScaleForMappingEmToPixels(&font->stbfont, 1) /
		stbtt_ScaleForPixelHeight(&font->stbfont, 1);
	res = stbtt_BakeFontBitmap(font->data, 0,
				   font->size * s,
				   (void*)set->image->ptr,
				   w, h, idx * 256, 256, set->glyphs);
	if (res < 0) {
		w *= 2;
		h *= 2;
		img_free(set->image);
		goto retry;
	}
	stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
	s = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
	int scaled_ascent = ascent * s + 0.5;
	for (i = 0; i < 256; i++) {
		set->glyphs[i].yoff += scaled_ascent;
		set->glyphs[i].xadvance = ceil(set->glyphs[i].xadvance);
	}
	for (i = w * h - 1; i >= 0; i--) {
		c = *(set->image->ptr + i);
		col[3] = c;
		memcpy(set->image->ptr + i * 4, col, 4);
	}
	return set;
}

static glyphset_t*
get_glyphset(font_t *font, int codepoint)
{
	int idx = (codepoint >> 8) % MAX_GLYPHSET;
	if (!font->sets[idx]) {
		font->sets[idx] = load_glyphset(font, idx);
	}
	return font->sets[idx];
}

int
font_height(font_t *font)
{
	return font->height;
}

int
font_width(font_t *font, const char *text)
{
	int x = 0;
	const char *p = text;
	unsigned codepoint, ocp = 0;
	int xend = 0, kern = 0;
	float s = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
	while (*p) {
		p = utf8_to_codepoint(p, &codepoint);
		glyphset_t *set = get_glyphset(font, codepoint);
		stbtt_bakedchar *g = &set->glyphs[codepoint & 0xff];
		if (ocp)
			kern = stbtt_GetCodepointKernAdvance(&font->stbfont, ocp, codepoint);
		ocp = codepoint;
		x += g->xadvance + ceil(kern * s);
		xend = g->xoff + g->x1 - g->x0;
		if (xend > g->xadvance)
			xend -= g->xadvance;
		else
			xend = 0;
	}
	return x + xend;
}

font_t*
font_load(const char *filename, float size)
{
	int ok;
	int ascent = 0, descent = 0, linegap = 0;
	float scale;
	font_t *font = NULL;
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
	ok = stbtt_InitFont(&font->stbfont, font->data, 0);
	if (!ok)
		goto err;
	stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
	scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, size);
	font->height = (ascent - descent + linegap) * scale + 0.5;
	return font;
err:
	if (fp)
		fclose(fp);
	if (font && font->data)
		free(font->data);
	free(font);
	return NULL;
}

int
font_render(font_t *font, const char *text, img_t *img)
{
	int x = 0, kern = 0;
	unsigned codepoint, ocp = 0;
	glyphset_t *set;
	stbtt_bakedchar *g;
	float s = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
	const char *p;
	p = text;
	while (*p) {
		p = utf8_to_codepoint(p, &codepoint);
		set = get_glyphset(font, codepoint);
		g = &set->glyphs[codepoint & 0xff];
		if (ocp)
			kern = stbtt_GetCodepointKernAdvance(&font->stbfont, ocp, codepoint);
		ocp = codepoint;
		x += ceil(s * kern);
		img_pixels_blend(set->image,
			g->x0, g->y0,
			g->x1 - g->x0, g->y1 - g->y0,
			img,
			x + g->xoff, g->yoff, PXL_BLEND_BLEND);
		x += g->xadvance;
	}
	return 0;
}

void
font_free(font_t *font)
{
	int i;
	for (i = 0; i < MAX_GLYPHSET; i++) {
		glyphset_t *set = font->sets[i];
		if (!set)
			continue;
		img_free(set->image);
		free(set);
	}
	free(font->data);
	free(font);
}

static const char *info = "stb_truetype";
const char *
font_renderer()
{
	return info;
}
