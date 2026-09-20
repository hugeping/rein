#ifndef __RECORD_H
#define __RECORD_H

/*
 * The GIF screen recorder (src/record.c): the caller feeds the frames
 * it draws (gfx.record_frame) and the file is written when the
 * recording stops or reaches its time limit.  `now` is the current
 * time in seconds: the recorder paces the frames itself.
 */
extern int RecordStart(const char *path, int fps);
extern int RecordFrame(const void *pixels, int width, int height, int pitch,
	double now);
extern int RecordStop(void);
extern int RecordOn(void);

#endif
