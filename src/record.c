/*
 * Screen recording: a fragment of the drawn frames into an animated
 * GIF, with msf_gif (see src/msf_gif.h).  The caller (gfx.c) feeds
 * the pixels frames; the file is written when the recording stops or
 * reaches its time limit.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "record.h"

#ifdef __EMSCRIPTEN__

/*
 * The browser has no file to write the clip into (and the hotkey
 * there belongs to its tools), so the recorder is a no-op.
 */
int
RecordStart(const char *path, int fps)
{
	(void)path;
	(void)fps;
	return 0;
}

int
RecordFrame(const void *pixels, int width, int height, int pitch, double now)
{
	(void)pixels;
	(void)width;
	(void)height;
	(void)pitch;
	(void)now;
	return 0;
}

int
RecordStop(void)
{
	return 0;
}

int
RecordOn(void)
{
	return 0;
}

#else

#define MSF_GIF_IMPL
#include "msf_gif.h"

#define RECORD_SECONDS 120

static MsfGifState state;
static char base[1024], path[1024];
static int on, begun, have_last, part;
static double last, frame_delay = 0.05, deadline;

/* the file of the current part: name.gif, name-2.gif, name-3.gif ... */
static void
record_path(void)
{
	const char *dot;
	size_t n;

	if (part <= 1) {
		snprintf(path, sizeof path, "%s", base);
		return;
	}
	dot = strrchr(base, '.');
	n = dot != NULL && dot != base ? (size_t)(dot - base) : strlen(base);
	snprintf(path, sizeof path, "%.*s-%d.gif", (int)n, base, part);
}

/* begin another gif; the recording itself goes on */
static int
record_new(int width, int height, double now)
{
	record_path();
	memset(&state, 0, sizeof state);
	if (!msf_gif_begin(&state, width, height)) {
		return 0;
	}
	begun = 1;
	have_last = 0;
	last = 0;
	deadline = now + RECORD_SECONDS;
	return 1;
}

static int
record_save(void)
{
	MsfGifResult res = msf_gif_end(&state);
	FILE *f;
	int ok;

	if (res.data == NULL) {
		return 0;
	}
	f = fopen(path, "wb");
	if (f == NULL) {
		msf_gif_free(res);
		return 0;
	}
	ok = fwrite(res.data, res.dataSize, 1, f) == 1;
	fclose(f);
	msf_gif_free(res);
	return ok;
}

static int
record_write(void)
{
	on = 0;
	return record_save();
}

int
RecordStart(const char *fname, int fps)
{
	if (on || fname == NULL) {
		return 0;
	}
	if (fps < 1) {
		fps = 1;
	}
	snprintf(base, sizeof base, "%s", fname);
	part = 1;
	frame_delay = 1.0 / fps;
	begun = 0;
	have_last = 0;
	last = 0;
	deadline = 0;
	on = 1;
	return 1;
}

int
RecordFrame(const void *pixels, int width, int height, int pitch, double now)
{
	int cs;

	if (!on) {
		return 0;
	}
	if (!begun) {
		if (width <= 0 || height <= 0 ||
			!record_new(width, height, now)) {
			on = 0;
			return 0;
		}
	} else if (width != state.width || height != state.height) {
		/* the screen size changed: save the clip and go on in
		   another file (a gif cannot mix frame sizes) */
		record_save();
		part ++;
		if (!record_new(width, height, now)) {
			on = 0;
			return 0;
		}
		fprintf(stdout, "recording: %s\n", path);
	}
	if (have_last && now - last < frame_delay) {
		return 1; /* too soon: the previous frame is still shown */
	}
	cs = have_last ? (int)((now - last) * 100 + 0.5) :
		(int)(frame_delay * 100 + 0.5);
	if (cs < 1) {
		cs = 1;
	}
	if (!msf_gif_frame(&state, (uint8_t *)pixels, cs, 16, pitch)) {
		on = 0; /* the library has freed its state already */
		return 0;
	}
	last = now;
	have_last = 1;
	if (now >= deadline) {
		return record_write(); /* the clip is long enough */
	}
	return 1;
}

int
RecordStop(void)
{
	if (!on) {
		return 0;
	}
	return record_write();
}

int
RecordOn(void)
{
	return on;
}

#endif
