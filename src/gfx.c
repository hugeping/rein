#include "external.h"
#include "stb_truetype.h"
#include "stb_image.h"
#include "stb_image_resize.h"
#include "platform.h"
#include "gfx.h"

static void
img_init(img_t *img, int w, int h)
{
	if (!img)
		return;
	img->w = w;
	img->h = h;
	img_noclip(img);
	img_offset(img, 0, 0);
}

img_t *
img_new(int w, int h)
{
	img_t *img = malloc(sizeof(img_t) + w * h * 4);
	if (!img)
		return NULL;
	img->ptr = (unsigned char *)(img + 1);
	img_init(img, w, h);
	return img;
}

void
img_noclip(img_t *img)
{
	if (!img)
		return;
	img->clip_x1 = 0;
	img->clip_y1 = 0;
	img->clip_x2 = img->w;
	img->clip_y2 = img->h;
}

void
img_offset(img_t *img, int x, int y)
{
	if (!img)
		return;
	img->xoff = x;
	img->yoff = y;
}

void
img_clip(img_t *img, int x1, int y1, int x2, int y2)
{
	if (!img)
		return;
	if (x1 > x2 || y1 > y2)
		return;
	x1 = (x1<0)?0:x1;
	x1 = (x1>=img->w)?img->w:x1;

	y1 = (y1<0)?0:y1;
	y1 = (y1>=img->h)?img->h:y1;

	x2 = (x2<0)?0:x2;
	x2 = (x2>=img->w)?img->w:x2;

	y2 = (y2<0)?0:y2;
	y2 = (y2>=img->h)?img->h:y2;

	img->clip_x1 = x1;
	img->clip_y1 = y1;
	img->clip_x2 = x2;
	img->clip_y2 = y2;
}

typedef struct {
	unsigned char r;
	unsigned char g;
	unsigned char b;
	unsigned char a;
} color_t;

static int
checkcolor(lua_State *L, int idx, color_t *col)
{
	if (!lua_istable(L, idx)) {
		col->r = col->g = col->b = 0;
		col->a = 255;
		return 0;
	}
	lua_rawgeti(L, idx, 1);
	lua_rawgeti(L, idx, 2);
	lua_rawgeti(L, idx, 3);
	lua_rawgeti(L, idx, 4);
	col->r = luaL_checknumber(L, -4);
	col->g = luaL_checknumber(L, -3);
	col->b = luaL_checknumber(L, -2);
	col->a = luaL_optnumber(L, -1, 255);
	lua_pop(L, 4);
	return 1;
}

#define PIXELS_MAGIC 0x1980

struct lua_pixels {
	int type;
	size_t size;
	img_t img;
};

static __inline void
blend(unsigned char *s, unsigned char *d)
{
	unsigned int r, g, b, a;
	unsigned int sa = s[3];
	unsigned int da = d[3];
	a = sa + (da * (255 - sa) >> 8);
	r = ((unsigned int)s[0] * sa >> 8) +
		((unsigned int)d[0] * da * (255 - sa) >> 16);
	g = ((unsigned int)s[1] * sa >> 8) +
		((unsigned int)d[1] * da * (255 - sa) >> 16);
	b = ((unsigned int)s[2] * sa >> 8) +
		((unsigned int)d[2] * da * (255 - sa) >> 16);
	d[0] = r; d[1] = g; d[2] = b; d[3] = a;
}

static __inline void
draw(unsigned char *s, unsigned char *d)
{
	unsigned int r, g, b, a;
	unsigned int sa = s[3];
	a = 255;
	r = ((unsigned int)s[0] * sa >> 8) +
		((unsigned int)d[0] * (255 - sa) >> 8);
	g = ((unsigned int)s[1] * sa >> 8) +
		((unsigned int)d[1] * (255 - sa) >> 8);
	b = ((unsigned int)s[2] * sa >> 8) +
		((unsigned int)d[2] * (255 - sa) >> 8);
	d[0] = r; d[1] = g; d[2] = b; d[3] = a;
}

static __inline void
pixel(unsigned char *s, unsigned char *d)
{
	unsigned char a_src = s[3];
	unsigned char a_dst = d[3];
	if (a_src == 255 || a_dst == 0) {
		memcpy(d, s, 4);
	} else if (a_dst == 255) {
		draw(s, d);
	} else if (a_src == 0) {
		/* nothing to do */
	} else {
		blend(s, d);
	}
}

static int
pixels_value(lua_State *L)
{
	struct lua_pixels *hdr = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	int x = luaL_optinteger(L, 2, -1);
	int y = luaL_optinteger(L, 3, -1);
	color_t col;
	int get = 0;
	unsigned char *ptr;
	if (!checkcolor(L, 4, &col))
		get = 1;

	if (x < 0 || y < 0)
		return 0;

	if (x >= hdr->img.w || y >= hdr->img.h)
		return 0;

	ptr = hdr->img.ptr;
	ptr += ((y * hdr->img.w + x) << 2);
	if (get) {
		lua_pushinteger(L, *(ptr ++));
		lua_pushinteger(L, *(ptr ++));
		lua_pushinteger(L, *(ptr ++));
		lua_pushinteger(L, *ptr);
		return 4;
	}
	*(ptr ++) = col.r;
	*(ptr ++) = col.g;
	*(ptr ++) = col.b;
	*(ptr) = col.a;
	return 0;
}

static int
pixels_pixel(lua_State *L)
{
	struct lua_pixels *hdr = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	int x = luaL_optnumber(L, 2, -1);
	int y = luaL_optnumber(L, 3, -1);
	color_t color;
	unsigned char col[4];
	unsigned char *ptr;

	checkcolor(L, 4, &color);

	x += hdr->img.xoff;
	y += hdr->img.yoff;

	if (x < hdr->img.clip_x1 || y < hdr->img.clip_y1)
		return 0;

	if (x >= hdr->img.clip_x2 || y >= hdr->img.clip_y2)
		return 0;

	ptr = hdr->img.ptr;
	ptr += ((y * hdr->img.w + x) << 2);
	col[0] = color.r; col[1] = color.g; col[2] = color.b; col[3] = color.a;
	pixel(col, ptr);
	return 0;
}

static int
pixels_buff(lua_State *L)
{
	int i;
	unsigned int col;
	struct lua_pixels *hdr = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	unsigned char *ptr = hdr->img.ptr;
	if (!lua_istable(L, 2)) { /* return actual table */
		lua_newtable(L);
		for (i = 0; i < hdr->img.w * hdr->img.h; i++) {
			col = *(ptr++);
			col = (col << 8) | *(ptr++);
			col = (col << 16) | *(ptr++);
			col = (col << 24) | *(ptr++);
			lua_pushnumber(L, col);
			lua_rawseti(L, -2, i + 1);
		}
		return 1;
	}
	for (i = 0; i < hdr->img.w * hdr->img.h; i ++) {
		lua_rawgeti(L, 2, i + 1);
		col = luaL_checknumber(L, -1);
		*(ptr++) = (col & 0xff000000) >> 24;
		*(ptr++) = (col & 0xff0000) >> 16;
		*(ptr++) = (col & 0xff00) >> 8;
		*(ptr++) = (col & 0xff);
		lua_pop(L, 1);
	}
	return 0;
}

static struct lua_pixels *
pixels_new(lua_State *L, int w, int h)
{
	size_t size;
	struct lua_pixels *hdr;

	if (w <=0 || h <= 0)
		return NULL;
	size = w * h * 4;
	hdr = lua_newuserdata(L, sizeof(*hdr) + size);
	if (!hdr)
		return 0;
	hdr->type = PIXELS_MAGIC;
	hdr->img.w = w;
	hdr->img.h = h;
	hdr->size = size;
	hdr->img.ptr = (unsigned char*)(hdr + 1);
	img_init(&hdr->img, w, h);
	memset(hdr->img.ptr, 0, size);
	luaL_getmetatable(L, "pixels metatable");
	lua_setmetatable(L, -2);
	return hdr;
}

static int
gfx_pixels_new(lua_State *L)
{
	int w, h, channels;
	struct lua_pixels *hdr;
	const char *fname;
	size_t size;
	unsigned char *b, *src, *dst;
	if (!lua_isnumber(L, 1)) {
		fname = luaL_optstring(L, 1, NULL);
		if (!fname)
			return 0;
		b = stbi_load(fname, &w, &h, &channels, 0);
		if (!b)
			return 0;
		if (!(hdr = pixels_new(L, w, h)))
			return 0;
		src = b; size = w * h * channels;
		dst = hdr->img.ptr;
		while ((size -= channels) > 0) {
			if (channels >= 4) /* rgba? */
				memcpy(dst, src, 4);
			else if (channels == 2) { /* grey alpha */
				memset(dst, src[0], 4);
				dst[3] = src[1];
			} else if (channels == 1) { /* grey */
				memset(dst, src[0], 4);
				dst[3] = 255;
			} else { /* rgb? */
				memset(dst, 0xff, 4);
				memcpy(dst, src, channels);
			}
			src += channels;
			dst += 4;
		}
		stbi_image_free(b);
		return 1;
	} else {
		w = luaL_optnumber(L, 1, -1);
		h = luaL_optnumber(L, 2, -1);
	}
	if (!pixels_new(L, w, h))
		return 0;
	return 1;
}

static img_t*
img_scale(img_t *src, float xscale, float yscale, int smooth)
{
	img_t *ret;
	int w = ceil(src->w * xscale);
	int h = ceil(src->h * yscale);
	ret = img_new(w, h);
	if (!ret)
		return NULL;
	stbir_resize_uint8(src->ptr, src->w, src->h, 0,
		ret->ptr, w, h, 0, 4);
	return ret;
}

static int
gfx_pixels_win(lua_State *L)
{
	struct lua_pixels *hdr;
	unsigned char *ptr;
	int w, h;
	hdr = lua_newuserdata(L, sizeof(*hdr));
	if (!hdr)
		return 0;
	ptr = WindowPixels(&w, &h);
	if (!ptr)
		return 0;
	hdr->type = PIXELS_MAGIC;
	hdr->img.w = w;
	hdr->img.h = h;
	img_init(&hdr->img, w, h);
	hdr->size = w * h * 4;
	hdr->img.ptr = ptr;
	//memset(hdr->img.ptr, 0, hdr->size);
	luaL_getmetatable(L, "pixels metatable");
	lua_setmetatable(L, -2);
	return 1;
}

static int
pixels_size(lua_State *L)
{
	struct lua_pixels *hdr = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	lua_pushinteger(L, hdr->img.w);
	lua_pushinteger(L, hdr->img.h);
	return 2;
}

static void
_fill(img_t *src, int x, int y, int w, int h,
		  int r, int g, int b, int a, int mode)
{
	unsigned char col[4];
	unsigned char *ptr1;
	int cy, cx;

	if (w)
		x += src->xoff;
	if (h)
		y += src->yoff;

	col[0] = r; col[1] = g; col[2] = b; col[3] = a;
	if (!w)
		w = src->w;
	if (!h)
		h = src->h;

	if (x < src->clip_x1) {
		w -= src->clip_x1 - x;
		x = src->clip_x1;
	}

	if (y < src->clip_y1) {
		h -= src->clip_y1 - y;
		y = src->clip_y1;
	}

	if (w <= 0 || h <= 0 || x >= src->clip_x2 || y >= src->clip_y2)
		return;

	if (x + w > src->clip_x2)
		w = src->clip_x2 - x;
	if (y + h > src->clip_y2)
		h = src->clip_y2 - y;

	ptr1 = src->ptr;
	ptr1 += (y * src->w + x) << 2;
	for (cy = 0; cy < h; cy ++) {
		unsigned char *p1 = ptr1;
		for (cx = 0; cx < w; cx ++) {
			if (mode == PXL_BLEND_COPY)
				memcpy(p1, col, 4);
			else
				pixel(col, p1);
			p1 += 4;
		}
		ptr1 += (src->w * 4);
	}
	return;
}


static int
pixels_fill(lua_State *L)
{
	int x = 0, y = 0, w = 0, h = 0;
	struct lua_pixels *src;
	color_t col;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");

	if (!lua_isnumber(L, 2)) {
		checkcolor(L, 2, &col);
	} else {
		x = luaL_optnumber(L, 2, 0);
		y = luaL_optnumber(L, 3, 0);
		w = luaL_optnumber(L, 4, 0);
		h = luaL_optnumber(L, 5, 0);
		checkcolor(L, 6, &col);
	}
	_fill(&src->img, x, y, w, h, col.r, col.g, col.b, col.a,
	      col.a == 255 ? PXL_BLEND_COPY:PXL_BLEND_BLEND);
	return 0;
}

static int
pixels_clear(lua_State *L)
{
	int x = 0, y = 0, w = 0, h = 0;
	struct lua_pixels *src;
	color_t col;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");

	if (!lua_isnumber(L, 2)) {
		checkcolor(L, 2, &col);
	} else {
		x = luaL_optnumber(L, 2, 0);
		y = luaL_optnumber(L, 3, 0);
		w = luaL_optnumber(L, 4, 0);
		h = luaL_optnumber(L, 5, 0);
		checkcolor(L, 6, &col);
	}
	_fill(&src->img, x, y, w, h, col.r, col.g, col.b, col.a, PXL_BLEND_COPY);
	return 0;
}

static void
img_pixels_stretch(img_t *src, img_t *dst, int xoff, int yoff, int ww, int hh)
{
	int w, h, xx, yy, dx, dy, xdisp, wdisp;
	unsigned char *ptr, *p;
	unsigned char *optr = NULL;
	ptr = src->ptr;

	xoff += dst->xoff;
	yoff += dst->yoff;

	if (ww < 0)
		ww = dst->w;

	if (hh < 0)
		hh = dst->h;

	if (xoff + ww <= dst->clip_x1 || yoff + hh <= dst->clip_y1 ||
		xoff >= dst->clip_x2 || yoff >= dst->clip_y2) {
		return;
	}

	w = src->w;
	h = src->h;

	p = dst->ptr + (yoff*dst->w + xoff)*4;

	dy = 0;

	xdisp = 0;
	wdisp = ww;
	if (xoff < dst->clip_x1) {
		xdisp = dst->clip_x1 - xoff;
		wdisp -= xdisp;;
		xdisp *= 4;
	}

	if (xoff + ww > dst->clip_x2)
		wdisp -= xoff + ww - dst->clip_x2;

	for (yy = yoff; yy < hh + yoff; yy++) {
		unsigned char *ptrl = ptr;

		if (yy >= dst->clip_y2)
			break;
		if (yy < dst->clip_y1) {
			if (optr)
				p += dst->w * 4;
			else {
				optr = p;
				p = optr + dst->w * 4;
			}
			goto skip;
		}

		dx = 0;
		if (optr) {
			memcpy(p + xdisp, optr + xdisp, wdisp * 4);
			p += dst->w * 4;
		} else {
			optr = p;
			for (xx = xoff; xx < xoff + ww; xx++) {
				if (xx >= dst->clip_x2)
					break;
				if (xx >= dst->clip_x1)
					memcpy(p, ptrl, 4);
				p += 4;
				dx += w;
				while (dx >= ww) {
					dx -= ww;
					ptrl += 4;
				}
			}
			p = optr + dst->w * 4;
		}
skip:
		dy += h;
		while (dy >= hh) {
			dy -= hh;
			ptr += (w << 2);
			optr = NULL;
		}
	}
}

int
img_pixels_blend(img_t *src, int x, int y, int w, int h,
			img_t *dst, int xx, int yy, int mode)
{
	unsigned char *ptr1, *ptr2;
	int cy, cx, srcw, dstw;

	x += src->xoff;
	y += src->xoff;
	xx += dst->xoff;
	yy += dst->yoff;

	if (!w)
		w = src->w;
	if (!h)
		h = src->h;

	if (x < 0 || x + w > src->w ||
		y < 0 || y + h > src->h)
		return 0;

	if (xx < dst->clip_x1) {
		w += xx - dst->clip_x1;
		x -= xx - dst->clip_x1;
		xx = dst->clip_x1;
	}

	if (w <= 0 || xx >= dst->clip_x2)
		return 0;

	if (yy < dst->clip_y1) {
		h += yy - dst->clip_y1;
		y -= yy - dst->clip_y1;
		yy = dst->clip_y1;
	}

	if (h <= 0 || yy >= dst->clip_y2)
		return 0;

	if (xx + w >= dst->clip_x2)
		w = dst->clip_x2 - xx;

	if (yy + h >= dst->clip_y2)
		h = dst->clip_y2 - yy;

	if (w <= 0 || h <= 0)
		return 0;

	ptr1 = src->ptr;
	ptr2 = dst->ptr;
	ptr1 += (y * src->w + x) << 2;
	ptr2 += (yy * dst->w + xx) << 2;
	srcw = src->w * 4; dstw = dst->w * 4;
	for (cy = 0; cy < h; cy ++) {
		if (mode == PXL_BLEND_COPY)
			memcpy(ptr2, ptr1, w << 2);
		else {
			unsigned char *p2 = ptr2;
			unsigned char *p1 = ptr1;
			for (cx = 0; cx < w; cx ++) {
				pixel(p1, p2);
				p1 += 4;
				p2 += 4;
			}
		}
		ptr2 += dstw;
		ptr1 += srcw;
	}
	return 0;
}

static int
pixels_copy(lua_State *L)
{
	int x = 0, y = 0, w = 0, h = 0, xx = 0, yy = 0;
	struct lua_pixels *src, *dst;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	dst = (struct lua_pixels*)lua_touserdata(L, 2);
	if (!dst) {
		x = luaL_optnumber(L, 2, 0);
		y = luaL_optnumber(L, 3, 0);
		w = luaL_optnumber(L, 4, 0);
		h = luaL_optnumber(L, 5, 0);
		dst = (struct lua_pixels*)luaL_checkudata(L, 6, "pixels metatable");
		xx = luaL_optnumber(L, 7, 0);
		yy = luaL_optnumber(L, 8, 0);
	} else {
		xx = luaL_optnumber(L, 3, 0);
		yy = luaL_optnumber(L, 4, 0);
	}
	if (dst->type != PIXELS_MAGIC)
		return 0;
	return img_pixels_blend(&src->img, x, y, w, h, &dst->img, xx, yy, PXL_BLEND_COPY);
}

static int
pixels_blend(lua_State *L)
{
	int x = 0, y = 0, w = 0, h = 0, xx = 0, yy = 0;
	struct lua_pixels *src, *dst;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	dst = (struct lua_pixels*)lua_touserdata(L, 2);
	if (!dst) {
		x = luaL_optnumber(L, 2, 0);
		y = luaL_optnumber(L, 3, 0);
		w = luaL_optnumber(L, 4, 0);
		h = luaL_optnumber(L, 5, 0);
		dst = (struct lua_pixels*)luaL_checkudata(L, 6, "pixels metatable");
		xx = luaL_optnumber(L, 7, 0);
		yy = luaL_optnumber(L, 8, 0);
	} else {
		xx = luaL_optnumber(L, 3, 0);
		yy = luaL_optnumber(L, 4, 0);
	}
	if (dst->type != PIXELS_MAGIC)
		return 0;
	return img_pixels_blend(&src->img, x, y, w, h, &dst->img, xx, yy, PXL_BLEND_BLEND);
}

static __inline void
line0(img_t *hdr, int x1, int y1, int dx, int dy, int xd, unsigned char *col)
{
	int dy2 = dy * 2;
	int dyx2 = dy2 - dx * 2;
	int err = dy2 - dx;
	unsigned char *ptr = NULL;

	int ly = hdr->w * 4;
	int lx = xd * 4;

	while ((x1 < hdr->clip_x1 || y1 < hdr->clip_y1 || x1 >= hdr->clip_x2) && dx --) {
		if (err >= 0) {
			y1 ++;
			err += dyx2;
		} else {
			err += dy2;
		}
		x1 += xd;
	}
	if (dx < 0)
		return;
	ptr = hdr->ptr;
	ptr += (y1 * hdr->w + x1) << 2;

	pixel(col, ptr);
	while (dx --) {
		if (err >= 0) {
			y1 ++;
			if (y1 >= hdr->clip_y2)
				break;
			ptr += ly;
			err += dyx2;
		} else {
			err += dy2;
		}
		x1 += xd;
		if (x1 >= hdr->clip_x2 || x1 < hdr->clip_x1)
			break;
		ptr += lx;
		pixel(col, ptr);
	}
	return;
}

static __inline void
line1(img_t *hdr, int x1, int y1, int dx, int dy, int xd, unsigned char *col)
{
	int dx2 = dx * 2;
	int dxy2 = dx2 - dy * 2;
	int err = dx2 - dy;
	unsigned char *ptr = NULL;
	int ly = hdr->w * 4;
	int lx = xd * 4;

	while ((x1 < hdr->clip_x1 || y1 < hdr->clip_y1 || x1 >= hdr->clip_x2) && dy --) {
		if (err >= 0) {
		        x1 += xd;
			err += dxy2;
		} else {
			err += dx2;
		}
		y1 ++;
	}
	if (dy < 0)
		return;

	ptr = hdr->ptr;
	ptr += (y1 * hdr->w + x1) << 2;

	pixel(col, ptr);

	while (dy --) {
		if (err >= 0) {
			x1 += xd;
			if (x1 < hdr->clip_x1 || x1 >= hdr->clip_x2)
				break;
			ptr += lx;
			err += dxy2;
		} else {
			err += dx2;
		}
		y1 ++;
		if (y1 >= hdr->clip_y2)
			break;
		ptr += ly;
		pixel(col, ptr);
	}
	return;
}

static void
line(img_t *src, int x1, int y1, int x2, int y2, int r, int g, int b, int a)
{
	int dx, dy, tmp;
	unsigned char col[4];
	x1 += src->xoff;
	y1 += src->yoff;
	x2 += src->xoff;
	y2 += src->yoff;

	if (y1 > y2) {
		tmp = y1; y1 = y2; y2 = tmp;
		tmp = x1; x1 = x2; x2 = tmp;
	}
	col[0] = r; col[1] = g; col[2] = b; col[3] = a;
	if (y1 >= src->clip_y2)
		return;
	if (y2 < src->clip_y1)
		return;
	if (x1 < x2) {
		if (x2 < src->clip_x1)
			return;
		if (x1 >= src->clip_x2)
			return;
	} else {
		if (x1 < src->clip_x1)
			return;
		if (x2 >= src->clip_x2)
			return;
	}
	dx = x2 - x1;
	dy = y2 - y1;
	if (dx > 0) {
		if (dx > dy) {
			line0(src, x1, y1, dx, dy, 1, col);
		} else {
			line1(src, x1, y1, dx, dy, 1, col);
		}
	} else {
		dx = -dx;
		if (dx > dy) {
			line0(src, x1, y1, dx, dy, -1, col);
		} else {
			line1(src, x1, y1, dx, dy, -1, col);
		}
	}
}

static int
pixels_line(lua_State *L)
{
	int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
	color_t col;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	x1 = luaL_optnumber(L, 2, 0);
	y1 = luaL_optnumber(L, 3, 0);
	x2 = luaL_optnumber(L, 4, 0);
	y2 = luaL_optnumber(L, 5, 0);
	checkcolor(L, 6, &col);
	line(&src->img, x1, y1, x2, y2, col.r, col.g, col.b, col.a);
	return 0;
}

static void
lineAA(img_t *src, int x0, int y0, int x1, int y1,
		 int r, int g, int b, int a)
{
	int dx, dy, err, e2, sx;
	int syp, sxp, ed;
	unsigned char *ptr;
	unsigned char col[4];

	x0 += src->xoff;
	y0 += src->yoff;
	x1 += src->xoff;
	y1 += src->yoff;

	col[0] = r; col[1] = g; col[2] = b; col[3] = a;
	if (y0 > y1) {
		int tmp;
		tmp = x0; x0 = x1; x1 = tmp;
		tmp = y0; y0 = y1; y1 = tmp;
	}
	if (y1 < src->clip_y1 || y0 >= src->clip_y2)
		return;
	if (x0 < x1) {
		sx = 1;
		if (x0 >= src->clip_x2 || x1 < src->clip_x1)
			return;
	} else {
		sx = -1;
		if (x1 >= src->clip_x2 || x0 < src->clip_x1)
			return;
	}
	sxp = sx * 4;
	syp = src->w * 4;

	dx =  abs(x1 - x0);
	dy = y1 - y0;

	err = dx - dy;
	ed = dx + dy == 0 ? 1: sqrt((float)dx * dx + (float)dy * dy);

	while (y0 < src->clip_y1 || x0 < src->clip_x1 || x0 >= src->clip_x2) {
		e2 = err;
		if (2 * e2 >= -dx) {
			if (x0 == x1)
				break;
			err -= dy;
			x0 += sx;
		}
		if (2 * e2 <= dy) {
			if (y0 == y1)
				break;
			err += dx;
			y0 ++;
		}
	}

	if (y0 < src->clip_y1 || x0 < src->clip_x1 || x0 >= src->clip_x2)
		return;

	ptr = (src->ptr);
	ptr += (y0 * src->w + x0) << 2;

	while (1) {
		unsigned char *optr = ptr;
		col[3] = a - a * abs(err - dx + dy) / ed;
		pixel(col, ptr);
		e2 = err;
		if (2 * e2 >= -dx) {
			if (x0 == x1)
				break;
			if (e2 + dy < ed) {
				col[3] = a - a * (e2 + dy) / ed;
				pixel(col, ptr + syp);
			}
			err -= dy;
			x0 += sx;
			if (x0 < src->clip_x1 || x0 >= src->clip_x2)
				break;
			ptr += sxp;
		}
		if (2 * e2 <= dy) {
			if (y0 == y1)
				break;
			if (dx - e2 < ed) {
				col[3] = a - a * (dx - e2) / ed;
				pixel(col, optr + sxp);
			}
			err += dx;
			y0 ++;
			if (y0 >= src->clip_y2)
				break;
			ptr += syp;
		}
	}
}

static int
pixels_lineAA(lua_State *L)
{
	int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
	color_t col;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	x1 = luaL_optnumber(L, 2, 0);
	y1 = luaL_optnumber(L, 3, 0);
	x2 = luaL_optnumber(L, 4, 0);
	y2 = luaL_optnumber(L, 5, 0);
	checkcolor(L, 6, &col);
	lineAA(&src->img, x1, y1, x2, y2, col.r, col.g, col.b, col.a);
	return 0;
}

static __inline int
orient2d(int ax, int ay, int bx, int by, int cx, int cy)
{
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

static __inline int
min3(int a, int b, int c)
{
	if (a < b) {
		if (a < c)
			return a;
		return c;
	} else {
		if (b < c)
			return b;
		return c;
	}
}

static __inline int
max3(int a, int b, int c)
{
	if (a > b) {
		if (a > c)
			return a;
		return c;
	} else {
		if (b > c)
			return b;
		return c;
	}
}

static void
triangle(img_t *src, int x0, int y0, int x1, int y1, int x2, int y2, int r, int g, int b, int a)
{
	int y, x, w;
	int yd;
	unsigned char col[4];
	unsigned char *ptr;
	int w0_row, w1_row, w2_row;

	int A01, A12, A20, B01, B12, B20, minx, miny, maxx, maxy;

	x0 += src->xoff;
	y0 += src->yoff;
	x1 += src->xoff;
	y1 += src->yoff;
	x2 += src->xoff;
	y2 += src->yoff;

	A01 = y0 - y1; B01 = x1 - x0;
	A12 = y1 - y2; B12 = x2 - x1;
	A20 = y2 - y0; B20 = x0 - x2;

	minx = min3(x0, x1, x2);
	miny = min3(y0, y1, y2);
	maxx = max3(x0, x1, x2);
	maxy = max3(y0, y1, y2);

	w = src->w;
	yd = 4 * w;
	col[0] = r; col[1] = b; col[2] = g; col[3] = a;

	if (minx >= src->clip_x2 || miny >= src->clip_y2)
		return;

	if (minx < src->clip_x1)
		minx = src->clip_x1;
	if (miny < src->clip_y1)
		miny = src->clip_y1;
	if (maxy >= src->clip_y2)
		maxy = src->clip_y2 - 1;
	if (maxx >= src->clip_x2)
		maxx = src->clip_x2 - 1;

	w0_row = orient2d(x1, y1, x2, y2, minx, miny);
	w1_row = orient2d(x2, y2, x0, y0, minx, miny);
	w2_row = orient2d(x0, y0, x1, y1, minx, miny);

	ptr = src->ptr + miny * yd + 4 * minx;

	for (y = miny; y <= maxy; y ++) {
		int w0 = w0_row;
		int w1 = w1_row;
		int w2 = w2_row;
		unsigned char *p = ptr;
		for (x = minx; x <= maxx; x++) {
			if ((w0 | w1 | w2) >= 0)
				pixel(col, p);
			p += 4;
			w0 += A12;
			w1 += A20;
			w2 += A01;
		}
		w0_row += B12;
		w1_row += B20;
		w2_row += B01;
		ptr += yd;
	}
}

static void
fill_circle(img_t *src, int xc, int yc, int radius, int r, int g, int b, int a)
{
	int r2 = radius * radius;
	int x, y, xx1, xx2, yy1, yy2;
	unsigned char col[4] = { r, g, b, a };
	int w = src->w;
	unsigned char *ptr;
	int x1, y1, x2, y2;

	xc += src->xoff;
	yc += src->yoff;

	x1 = src->clip_x1;
	y1 = src->clip_y1;
	x2 = src->clip_x2;
	y2 = src->clip_y2;

	if (xc + radius < x1 || yc + radius < y1)
		return;
	if (xc - radius >= x2 || yc - radius >= y2)
		return;

	if (radius <= 0)
		return;

	ptr = src->ptr;
	ptr += (w * yc + xc) << 2;

	if (radius == 1) {
		pixel(col, ptr);
		return;
	}
	yy1 = -radius; yy2 = radius;
	xx1 = -radius; xx2 = radius;
	if (yc - radius < y1)
		yy1 = -(yc - y1);
	if (xc - radius < x1)
		xx1 = -(xc - x1);
	if (xc + radius >= x2)
		xx2 = x2 - xc - 1;
	if (yc + radius >= y2)
		yy2 = y2 - yc - 1;
	for (y = yy1; y <= yy2; y ++) {
		unsigned char *ptrl = ptr + ((y * w + xx1) << 2);
		for (x = xx1; x <= xx2; x++) {
			if (x*x + y*y < r2 - 1)
				pixel(col, ptrl);
			ptrl += 4;
		}
	}
}

static void
circle(img_t *src, int xc, int yc, int rr, int r, int g, int b, int a)
{
	int x = -rr, y = 0, err = 2 - 2 * rr;
	unsigned char *ptr = src->ptr;
	unsigned char col[4] = { r, g, b, a };
	int w = src->w;
	int x1, y1, x2, y2;

	if (rr <= 0)
		return;

	xc += src->xoff;
	yc += src->yoff;

	x1 = src->clip_x1;
	y1 = src->clip_y1;
	x2 = src->clip_x2;
	y2 = src->clip_y2;

	if (xc + rr < x1 || yc + rr < y1)
		return;
	if (xc - rr >= x2 || yc - rr >= y2)
		return;

	ptr += (w * yc + xc) * 4;
	if (xc - rr >= x1 && xc + rr < x2 &&
	    yc - rr >= y1 && yc + rr < y2) {
		do {
			int xmy = (x - y * w) * 4;
			int yax = (y + x * w) * 4;
			pixel(col, ptr - xmy);
			pixel(col, ptr - yax);
			pixel(col, ptr + xmy);
			pixel(col, ptr + yax);

			rr = err;
			if (rr <= y)
				err += ++y * 2 + 1;
			if (rr > x || err > y)
				err += ++x * 2 + 1;
		} while (x < 0);
		return;
	}
	/* slow */
	do {
		int xmy = (x - y * w) * 4;
		int yax = (y + x * w) * 4;
		if (((xc - x - x1) | (x2 - xc + x - 1) |
		    (yc + y - y1) | (y2 - yc - y - 1)) >= 0)
			pixel(col, ptr - xmy);
		if (((xc - y - x1) | (x2 - xc + y - 1) |
		     (yc - x - y1) | (y2 - yc + x - 1)) >= 0)
			pixel(col, ptr - yax);
		if (((xc + x - x1) | (x2 - xc - x - 1) |
		     (yc - y - y1) | (y2 - yc + y - 1)) >= 0)
			pixel(col, ptr + xmy);
		if (((xc + y - x1) | (x2 - xc - y - 1) |
		      (yc + x - y1) | (y2 - yc - x - 1)) >= 0)
			pixel(col, ptr + yax);
		rr = err;
		if (rr <= y)
			err += ++y * 2 + 1;
		if (rr > x || err > y)
			err += ++x * 2 + 1;
	} while (x < 0);

}
static void
circleAA(img_t *src, int xc, int yc, int rr, int r, int g, int b, int a)
{
	int p1, p2, p3, p4;
	int x = -rr, y = 0, xx2, e2, err = 2 - 2 * rr;
	unsigned char *ptr = src->ptr;
	unsigned char col[4] = { r, g, b, a };
	int w = src->w;
	int x1, y1, x2, y2;

	xc += src->xoff;
	yc += src->yoff;

	x1 = src->clip_x1;
	y1 = src->clip_y1;
	x2 = src->clip_x2;
	y2 = src->clip_y2;

	if (rr <= 0)
		return;
	if (xc + rr < x1 || yc + rr < y1)
		return;
	if (xc - rr >= x2 || yc - rr >= y2)
		return;
	rr = 1 - err;
	ptr += (w * yc + xc) * 4;
	do {
		int i = 255 * abs(err - 2 *(x + y)-2) / rr;
		int xmy = (x - y * w) * 4;
		int yax = (y + x * w) * 4;
		col[3] = ((255 - i) * a) >> 8;
		p1 = 0; p2 = 0; p3 = 0; p4 = 0;
		if (((xc - x - x1) | (x2 - xc + x - 1) |
		     (yc + y - y1) | (y2 - yc - y - 1)) >= 0) {
			pixel(col, ptr - xmy);
			p1 = 1;
		}
		if (((xc - y - x1) | (x2 - xc + y - 1) |
		     (yc - x - y1) | (y2 - yc + x - 1)) >= 0) {
			pixel(col, ptr - yax);
			p2 = 1;
		}
		if (((xc + x - x1) | (x2 - xc - x - 1) |
		     (yc - y - y1) | (y2 - yc + y - 1)) >= 0) {
			pixel(col, ptr + xmy);
			p3 = 1;
		}
		if (((xc + y - x1) | (x2 - xc - y - 1) |
		     (yc + x - y1) | (y2 - yc - x - 1)) >= 0) {
			pixel(col, ptr + yax);
			p4 = 1;
		}
		e2 = err;
		xx2 = x;
		if (err + y > 0) {
			i = 255 * (err - 2 * x - 1) / rr;
			if (i < 256) {
				col[3] = ((255 - i) * a) >> 8;
				if (p1 && yc + y + 1 < y2)
					pixel(col, ptr - xmy + w * 4);
				if (p2 && xc - y - 1 >= x1)
					pixel(col, ptr - yax - 4);
				if (p3 && yc - y - 1 >= y1)
					pixel(col, ptr + xmy - w * 4);
				if (p4 && xc + y < x2)
					pixel(col, ptr + yax + 4);
			}
			err += ++x * 2 + 1;
		}
		if (e2 + x <= 0) {
			i = 255 * (2 * y + 3 - e2) / rr;
			if (i < 256) {
				col[3] = ((255 - i) * a) >> 8;
				if (p1 && xc - xx2 - 1 >= x1)
					pixel(col, ptr - xmy - 4);
				if (p2 && yc - xx2 - 1 >= y1)
					pixel(col, ptr - yax - w * 4);
				if (p3 && xc + xx2 + 1 < x2)
					pixel(col, ptr + xmy + 4);
				if (p4 && yc + xx2 + 1 < y2)
					pixel(col, ptr + yax + w * 4);
			}
			err += ++y * 2 + 1;
		}
	} while (x < 0);
}

struct lua_point {
	int x;
	int y;
	int nodex;
};

/*
   http://alienryderflex.com/polygon_fill/
   public-domain code by Darel Rex Finley, 2007
*/

static void
fill_poly(img_t *src, struct lua_point *v, int nr, unsigned char *col)
{
	unsigned char *ptr = src->ptr, *ptr1;
	int y, x, xmin, xmax, ymin, ymax, swap, w;
	int nodes = 0, j, i;
	xmin = v[0].x; xmax = v[0].x;
	ymin = v[0].y; ymax = v[0].y;

	for (i = 0; i < nr; i++) {
		if (v[i].x < xmin)
			xmin = v[i].x;
		if (v[i].x > xmax)
			xmax = v[i].x;
		if (v[i].y < ymin)
			ymin = v[i].y;
		if (v[i].y > ymax)
			ymax = v[i].y;
	}
	if (ymin < src->clip_y1)
		ymin = src->clip_y1;
	if (xmin < src->clip_x1)
		xmin = src->clip_x1;
	if (xmax >= src->clip_x2)
		xmax = src->clip_x2;
	if (ymax >= src->clip_y2)
		ymax = src->clip_y2;
	ptr += (ymin * src->w) << 2;
	for (y = ymin; y < ymax; y ++) {
		nodes = 0; j = nr - 1;
		for (i = 0; i < nr; i++) {
			if ((v[i].y < y && v[j].y >= y) ||
			    (v[j].y < y && v[i].y >= y)) {
				v[nodes ++].nodex = v[i].x + ((y - v[i].y) * (v[j].x - v[i].x)) /
					(v[j].y - v[i].y);
			}
			j = i;
		}
		if (nodes < 2)
			goto skip;
		i = 0;
		while (i < nodes - 1) { /* sort */
			if (v[i].nodex > v[i + 1].nodex) {
				swap = v[i].nodex;
				v[i].nodex = v[i + 1].nodex;
				v[i + 1].nodex = swap;
				if (i)
					i --;
			} else {
				i ++;
			}
		}
		for (i = 0; i < nodes; i += 2) {
			if (v[i].nodex >= xmax)
				break;
			if (v[i + 1].nodex > xmin) {
				if (v[i].nodex < xmin)
					v[i].nodex = xmin;
				if (v[i + 1].nodex > xmax)
					v[i + 1].nodex = xmax;
				// hline
				w = (v[i + 1].nodex - v[i].nodex);
				ptr1 = ptr + v[i].nodex * 4;
				for (x = 0; x < w; x ++) {
					pixel(col, ptr1);
					ptr1 += 4;
				}
			}
		}
	skip:
		ptr += src->w * 4;
	}
}

static int
pixels_triangle(lua_State *L)
{
	int x0 = 0, y0 = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0;
	struct lua_pixels *src;
	color_t col;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	x0 = luaL_optnumber(L, 2, 0);
	y0 = luaL_optnumber(L, 3, 0);
	x1 = luaL_optnumber(L, 4, 0);
	y1 = luaL_optnumber(L, 5, 0);
	x2 = luaL_optnumber(L, 6, 0);
	y2 = luaL_optnumber(L, 7, 0);
	#define XOR_SWAP(x,y) x=x^y; y=x^y; x=x^y;
	if (orient2d(x0, y0, x1, y1, x2, y2) < 0) {
		XOR_SWAP(x1, x2)
		XOR_SWAP(y1, y2)
	}
	#undef XOR_SWAP
	checkcolor(L, 8, &col);
	triangle(&src->img, x0, y0, x1, y1, x2, y2, col.r, col.g, col.b, col.a);
	return 0;
}

static int
pixels_circle(lua_State *L)
{
	int xc = 0, yc = 0, rr = 0;
	color_t col;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	xc = luaL_optnumber(L, 2, 0);
	yc = luaL_optnumber(L, 3, 0);
	rr = luaL_optnumber(L, 4, 0);
	checkcolor(L, 5, &col);
	circle(&src->img, xc, yc, rr, col.r, col.g, col.b, col.a);
	return 0;
}

static int
pixels_circleAA(lua_State *L)
{
	int xc = 0, yc = 0, rr = 0;
	color_t col;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	xc = luaL_optnumber(L, 2, 0);
	yc = luaL_optnumber(L, 3, 0);
	rr = luaL_optnumber(L, 4, 0);
	checkcolor(L, 5, &col);
	circleAA(&src->img, xc, yc, rr, col.r, col.g, col.b, col.a);
	return 0;
}

static int
pixels_fill_circle(lua_State *L)
{
	int xc = 0, yc = 0, rr = 0;
	color_t col;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	xc = luaL_optnumber(L, 2, 0);
	yc = luaL_optnumber(L, 3, 0);
	rr = luaL_optnumber(L, 4, 0);
	checkcolor(L, 5, &col);
	fill_circle(&src->img, xc, yc, rr, col.r, col.g, col.b, col.a);
	return 0;
}

static int
pixels_fill_poly(lua_State *L)
{
	int nr, i;
	struct lua_pixels *src;
	struct lua_point *v;
	unsigned char col[4];
	color_t color;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	luaL_checktype(L, 2, LUA_TTABLE);
#if LUA_VERSION_NUM >= 502
	nr = lua_rawlen(L, 2);
#else
	nr = lua_objlen(L, 2);
#endif
	if (nr < 6)
		return 0;
	checkcolor(L, 3, &color);
	col[0] = color.r;
	col[1] = color.g;
	col[2] = color.b;
	col[3] = color.a;

	nr /= 2;
	v = malloc(sizeof(*v) * nr);
	if (!v)
		return 0;
	lua_pushvalue(L, 2);
	for (i = 0; i < nr; i++) {
		lua_pushinteger(L, (i * 2) + 1);
		lua_gettable(L, -2);
		v[i].x = lua_tonumber(L, -1) + src->img.xoff;
		lua_pop(L, 1);
		lua_pushinteger(L, (i * 2) + 2);
		lua_gettable(L, -2);
		v[i].y = lua_tonumber(L, -1) + src->img.yoff;
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
	fill_poly(&src->img, v, nr, col);
	free(v);
	return 0;
}

static int
pixels_scale(lua_State *L)
{
	float xs, ys;
	int smooth;
	struct lua_pixels *src;
	img_t *dst;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	xs = luaL_optnumber(L, 2, 0.0f);
	ys = luaL_optnumber(L, 3, 0.0f);
	if (ys == 0.0)
		ys = xs;
	smooth = lua_toboolean(L, 4);
	dst = img_scale(&src->img, xs, ys, smooth);
	if (!dst)
		return 0;
	src = pixels_new(L, dst->w, dst->h);
	if (!src) {
		free(dst);
		return 0;
	}
	memcpy(src->img.ptr, dst->ptr, src->size);
	free(dst);
	return 1;
}

static int
pixels_stretch(lua_State *L)
{
	struct lua_pixels *src;
	struct lua_pixels *dst;
	int x, y, w, h;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	dst = (struct lua_pixels*)luaL_checkudata(L, 2, "pixels metatable");

	x = luaL_optinteger(L, 3, 0);
	y = luaL_optinteger(L, 4, 0);
	w = luaL_optinteger(L, 5, -1);
	h = luaL_optinteger(L, 6, -1);

	img_pixels_stretch(&src->img, &dst->img, x, y, w, h);
	return 0;
}

static int
pixels_clip(lua_State *L)
{
	int x1, y1, x2, y2;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	if (lua_isnil(L, 2)) {
		lua_pushinteger(L, src->img.clip_x1);
		lua_pushinteger(L, src->img.clip_y1);
		lua_pushinteger(L, src->img.clip_x2);
		lua_pushinteger(L, src->img.clip_y2);
		return 4;
	}
	x1 = luaL_checkinteger(L, 2);
	y1 = luaL_checkinteger(L, 3);
	x2 = luaL_checkinteger(L, 4);
	y2 = luaL_checkinteger(L, 5);
	if (x2 < 0)
		x2 = src->img.w - x2;
	if (y2 < 0)
		y2 = src->img.h - y2;
	img_clip(&src->img, x1, y1, x2, y2);
	return 0;
}

static int
pixels_noclip(lua_State *L)
{
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	img_noclip(&src->img);
	return 0;
}

static int
pixels_offset(lua_State *L)
{
	int x, y;
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	if (lua_isnil(L, 2)) {
		lua_pushinteger(L, src->img.xoff);
		lua_pushinteger(L, src->img.yoff);
		return 2;
	}
	x = luaL_checkinteger(L, 2);
	y = luaL_checkinteger(L, 3);
	img_offset(&src->img, x, y);
	return 0;
}

static int
pixels_nooffset(lua_State *L)
{
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	img_offset(&src->img, 0, 0);
	return 0;
}

static const luaL_Reg pixels_mt[] = {
	{ "val", pixels_value },
	{ "clip", pixels_clip },
	{ "npclip", pixels_noclip },
	{ "offset", pixels_offset },
	{ "nooffset", pixels_nooffset },
	{ "pixel", pixels_pixel },
	{ "buff", pixels_buff },
	{ "size", pixels_size },
	{ "fill", pixels_fill },
	{ "clear", pixels_clear },
	{ "copy", pixels_copy },
	{ "blend", pixels_blend },
	{ "line", pixels_line },
	{ "lineAA", pixels_lineAA },
	{ "fill_triangle", pixels_triangle },
	{ "circle", pixels_circle },
	{ "circleAA", pixels_circleAA },
	{ "fill_circle", pixels_fill_circle },
	{ "fill_poly", pixels_fill_poly },
	{ "scale", pixels_scale },
	{ "stretch", pixels_stretch },
	{ NULL, NULL }
};

static void
pixels_create_meta(lua_State *L)
{
	luaL_newmetatable (L, "pixels metatable");
	luaL_setfuncs_int(L, pixels_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
}

int
gfx_flip(lua_State *L)
{
	int x, y, w, h;
	x = luaL_optnumber(L, 1, 0);
	y = luaL_optnumber(L, 2, 0);
	w = luaL_optnumber(L, 3, -1);
	h = luaL_optnumber(L, 4, -1);
	WindowUpdate(x, y, w, h);
	return 0;
}

static int
gfx_icon(lua_State *L)
{
	struct lua_pixels *src;
	src = (struct lua_pixels*)luaL_checkudata(L, 1, "pixels metatable");
	Icon(src->img.ptr, src->img.w, src->img.h);
	return 0;
}

#define FONT_MAGIC 0x1978

struct lua_font {
	int type;
	font_t *font;
};

static int
font_gc(lua_State *L)
{
	struct lua_font *fn = (struct lua_font*)luaL_checkudata(L, 1, "font metatable");
	font_free(fn->font);
	return 0;
}

static int
font_size(lua_State *L)
{
	struct lua_font *fn = (struct lua_font*)luaL_checkudata(L, 1, "font metatable");
	const char *text = luaL_checkstring(L, 2);
	lua_pushinteger(L, font_width(fn->font, text));
	lua_pushinteger(L, font_height(fn->font));
	return 2;
}

static void
img_colorize(img_t *img, color_t *col)
{
	unsigned char *ptr = img->ptr;
	size_t size = img->w * img->h * 4;
	while (size -= 4) { /* colorize! */
		memcpy(ptr, col, 3);
		ptr[3] = ptr[3] * col->a / 255;
		ptr += 4;
	}
}

static int
font_text(lua_State *L)
{
	int w, h;
	color_t col;
	struct lua_pixels *pxl;
	struct lua_font *fn = (struct lua_font*)luaL_checkudata(L, 1, "font metatable");
	const char *text = luaL_checkstring(L, 2);
	checkcolor(L, 3, &col);
	w = font_width(fn->font, text);
	h = font_height(fn->font);
	pxl = pixels_new(L, w, h);
	if (!pxl)
		return 0;
	memset(pxl->img.ptr, 0, pxl->img.w * pxl->img.h * 4);
	font_render(fn->font, text, &pxl->img);
	img_colorize(&pxl->img, &col);
	return 1;
}

static const luaL_Reg font_mt[] = {
	{ "__gc", font_gc },
	{ "size", font_size },
	{ "text", font_text },
	{ NULL, NULL }
};

static void
font_create_meta(lua_State *L)
{
	luaL_newmetatable(L, "font metatable");
	luaL_setfuncs_int(L, font_mt, 0);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
}

int
gfx_font(lua_State *L)
{
	const char *filename  = luaL_checkstring(L, 1);
	float size = luaL_checknumber(L, 2);
	font_t *font;
	struct lua_font *fn;

	font = font_load(filename, size);
	if (!font)
		return 0;
	fn = lua_newuserdata(L, sizeof(*fn));
	if (!fn) {
		free(font);
		return 0;
	}
	luaL_getmetatable(L, "font metatable");
	lua_setmetatable(L, -2);
	fn->type = FONT_MAGIC;
	fn->font = font;
	return 1;
}

const char*
utf8_to_codepoint(const char *p, unsigned *dst)
{
	unsigned res, n;
	switch (*p & 0xf0) {
		case 0xf0 :  res = *p & 0x07;  n = 3;  break;
		case 0xe0 :  res = *p & 0x0f;  n = 2;  break;
		case 0xd0 :
		case 0xc0 :  res = *p & 0x1f;  n = 1;  break;
		default   :  res = *p;         n = 0;  break;
	}
	while (n-- && *p)
		res = (res << 6) | (*(++p) & 0x3f);
	*dst = res;
	return p + 1;
}

static const luaL_Reg
gfx_lib[] = {
	{ "win",  gfx_pixels_win },
	{ "new", gfx_pixels_new },
	{ "icon", gfx_icon },
	{ "flip", gfx_flip },
	{ "font", gfx_font },
	{ NULL, NULL }
};

int
gfx_init(lua_State *L)
{
	pixels_create_meta(L);
	font_create_meta(L);
	luaL_newlib(L, gfx_lib);
	return 0;
}
