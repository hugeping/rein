typedef struct {
	int w;
	int h;
	int clip_x1;
	int clip_y1;
	int clip_x2;
	int clip_y2;
	int xoff;
	int yoff;
	int used;
	unsigned char *ptr;
} img_t;

extern img_t *img_new(int w, int h);
extern void img_free(img_t *src);
#define PXL_BLEND_COPY 1
#define PXL_BLEND_BLEND 2

extern int img_pixels_blend(img_t *src, int x, int y, int w, int h,
	img_t *dst, int xx, int yy, int mode);

struct _font_t;
typedef struct _font_t font_t;

extern font_t* font_load(const char *filename, float size);
extern void font_free(font_t *font);
extern int font_width(font_t *font, const char *text);
extern int font_render(font_t *font, const char *text, img_t *img);
extern int font_height(font_t *font);
const char *font_renderer(void);

extern const char* utf8_to_codepoint(const char *p, unsigned *dst);
extern int gfx_udata_move(lua_State *from, int idx, lua_State *to);
extern void pixels_create_meta(lua_State *L);
