#ifndef __PLATFORM_H
#define __PLATFORM_H
extern int PlatformInit(void);
extern void PlatformDone(void);

extern void Delay(float n);
extern int WaitEvent(float n);

extern int WindowCreate(void);
extern void WindowResize(int w, int h);
extern void WindowUpdate(int x, int y, int w, int h);
extern unsigned char *WindowPixels(int *w, int *h);

enum { WIN_NORMAL, WIN_MAXIMIZED, WIN_FULLSCREEN };
extern void WindowMode(int n);
extern void WindowTitle(const char *title);

extern double Time(void);
extern float GetScale(void);

extern const char *GetPlatform(void);
extern const char *GetExePath(const char *progname);

extern void Icon(unsigned char *ptr, int w, int h);
extern unsigned int AudioWrite(void *data, unsigned int size);

extern int sys_poll(lua_State *L);
extern void TextInput(void);

extern void Log(const char *msg);

extern int Thread(int (*fn) (void *), void *data);
extern int ThreadWait(int tid);

extern int Mutex(void);
extern int MutexDestroy(int mid);
extern int MutexLock(int mid);
extern int MutexUnlock(int mid);

extern int Sem(int counter);
extern int SemDestroy(int sid);
extern int SemWait(int sid);
extern int SemPost(int sid);

/* extern void MouseHide(int hide); */

#endif
