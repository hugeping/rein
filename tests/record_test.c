/*
 * A smoke test for the gif screen recorder: three small frames in,
 * one gif file out.  Run by tests/run.sh.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "record.h"

static int checks, failures;

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

/* is the color an entry of the local color table? */
static int
color_in_palette(const unsigned char *buf, size_t len, int r, int g, int b)
{
	size_t i;
	int j, packed, entries;

	for (i = 0; i + 10 < len; i ++) {
		if (buf[i] != 0x2C) { /* an image descriptor */
			continue;
		}
		packed = buf[i + 9];
		if (!(packed & 0x80)) {
			continue;
		}
		entries = 2 << (packed & 7);
		if (i + 10 + (size_t)entries * 3 > len) {
			continue;
		}
		for (j = 0; j < entries; j ++) {
			const unsigned char *c = buf + i + 10 + j * 3;

			if (c[0] == r && c[1] == g && c[2] == b) {
				return 1;
			}
		}
		return 0;
	}
	return 0;
}

static int
gif_size(const char *file, int *w, int *h)
{
	unsigned char b[10];
	FILE *f = fopen(file, "rb");

	if (f == NULL) {
		return 0;
	}
	if (fread(b, 1, sizeof b, f) != sizeof b) {
		fclose(f);
		return 0;
	}
	fclose(f);
	*w = b[6] | (b[7] << 8);
	*h = b[8] | (b[9] << 8);
	return 1;
}

int
main(void)
{
	static const char *path = "record_test.gif";
	static unsigned char file[65536];
	unsigned char px[8 * 8 * 4];
	unsigned char head[6], tail;
	size_t n;
	int i, w, h;
	FILE *f;

	for (i = 0; i < (int)sizeof px; i += 4) {
		px[i] = (unsigned char)i;
		px[i + 1] = 0x40;
		px[i + 2] = (unsigned char)(255 - i);
		px[i + 3] = 255;
	}
	printf("# recorder\n");
	chk(RecordStart(path, 20), "start");
	chk(!RecordStart(path, 20), "a second start");
	chk(RecordOn(), "the recording is on");
	for (i = 0; i < 3; i ++) {
		chk(RecordFrame(px, 8, 8, 8 * 4, i * 0.1), "frame");
	}
	chk(RecordStop(), "stop");
	chk(!RecordOn(), "the recording is off");
	chk(!RecordStop(), "a second stop writes nothing");

	f = fopen(path, "rb");
	chk(f != NULL, "the file exists");
	chk(f && fread(head, 1, sizeof head, f) == sizeof head &&
		memcmp(head, "GIF89a", 6) == 0, "the gif header");
	if (f) {
		tail = 0;
		fseek(f, -1, SEEK_END);
		chk(fread(&tail, 1, 1, f) == 1 && tail == 0x3B,
			"the gif trailer");
		chk(ftell(f) > 6, "some data");
		fclose(f);
	}
	remove(path);

	/* the colors are kept as they are: a single pure red pixel */
	chk(RecordStart(path, 20), "start a color test");
	memset(px, 0, sizeof px);
	px[0] = 255;   /* red */
	px[1] = 0;
	px[2] = 0;
	px[3] = 255;   /* alpha */
	chk(RecordFrame(px, 1, 1, 4, 0), "one red pixel");
	chk(RecordStop(), "stop the color test");
	f = fopen(path, "rb");
	n = f ? fread(file, 1, sizeof file, f) : 0;
	if (f) {
		fclose(f);
	}
	chk(color_in_palette(file, n, 255, 0, 0), "the red is red");
	chk(!color_in_palette(file, n, 0, 0, 255), "the red is not blue");
	remove(path);

	/* the clip stops by itself at the time limit: the frames are
	   thirty seconds apart, so the fifth one crosses the limit */
	chk(RecordStart(path, 20), "start a long test");
	for (i = 0; i < 4; i ++) {
		chk(RecordFrame(px, 8, 8, 8 * 4, i * 30.0), "a long frame");
	}
	chk(RecordOn(), "still recording under the limit");
	chk(RecordFrame(px, 8, 8, 8 * 4, 120.0), "the limit frame");
	chk(!RecordOn(), "the limit stops the recording");
	chk(!RecordFrame(px, 8, 8, 8 * 4, 121.0), "no frames after the limit");
	remove(path);

	/* a frame of another size saves the clip and starts another */
	chk(RecordStart(path, 20), "start a resize test");
	chk(RecordFrame(px, 8, 8, 8 * 4, 0), "a frame of the clip size");
	chk(RecordFrame(px, 4, 4, 4 * 4, 1), "a frame of another size");
	chk(RecordOn(), "the resize goes on in a new file");
	chk(RecordStop(), "stop the resize test");
	chk(gif_size(path, &w, &h) && w == 8 && h == 8,
		"the first part keeps its size");
	chk(gif_size("record_test-2.gif", &w, &h) && w == 4 && h == 4,
		"the second part is the new size");
	remove(path);
	remove("record_test-2.gif");

	printf("%d checks, %d failures\n", checks, failures);
	return failures != 0;
}
