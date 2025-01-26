#ifndef __PLATFORM_H
#define __PLATFORM_H

extern int PlatformInit(int argc, const char **argv);
extern void PlatformDone(void);

extern void Delay(float n);
extern int WaitEvent(float n);
extern void WakeEvent(void);

extern void Flip(void);
extern int WindowCreate(void);
extern void WindowSize(int *w, int *h);
extern void WindowResize(int w, int h);
extern void WindowClear(int r, int g, int b);

enum { WIN_NORMAL, WIN_MAXIMIZED, WIN_FULLSCREEN };
extern void WindowMode(int n);
extern void WindowTitle(const char *title);

extern double Time(void);
extern float GetScale(void);
extern unsigned int GetMouse(int *ox, int *oy);

extern const char *GetPlatform(void);
extern const char *GetLanguage(void);
extern const char *GetExePath(const char *progname);

extern void Icon(unsigned char *ptr, int w, int h);
extern unsigned int AudioWrite(void *data, unsigned int size);

extern int sys_poll(lua_State *L);
extern void TextInput(void);

extern void Log(const char *msg);

extern int Thread(int (*fn) (void *), void *data);
extern int ThreadWait(int tid);
extern void ThreadDetach(int id);

extern int Mutex(void);
extern int MutexDestroy(int mid);
extern int MutexLock(int mid);
extern int MutexUnlock(int mid);

extern int Sem(int counter);
extern int SemDestroy(int sid);
extern int SemWait(int sid, int ms);
extern int SemPost(int sid);

extern void MouseHide(int hide);
extern int Dial(const char *host, const char *port);
extern int Send(int fd, const void *data, int size);
extern int Recv(int fd, void *data, int size);
extern void Shutdown(int fd);

extern char *Clipboard(const char *text);

extern char *GetRealpath(const char *path);
extern int IsAbsolutePath(const char *path);

extern void *SpriteCreate(void *pixels, int w, int h);
extern void SpriteFree(void *spr);
extern void SpriteBlend(void *spr, int x, int y, int w, int h);
extern void SpriteUpdate(void *s, void *pixels, int w, int h);

#endif
