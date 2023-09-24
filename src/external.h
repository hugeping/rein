#ifdef _WIN32
 #include <winsock2.h>
 #include <ws2tcpip.h>
 #include <windows.h>
 #include <windows.h>
#else
 #include <signal.h>
 #include <unistd.h>
 #include <arpa/inet.h>
 #include <netdb.h>
 #include <sys/socket.h>
#endif
#ifdef __linux__
 #include <sys/wait.h>
#endif
#include <dirent.h>
#include <libgen.h>
#ifdef __ANDROID__
#include <SDL_system.h>
#endif
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <math.h>
#include <time.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "lua-compat.h"
#ifdef __EMSCRIPTEN__
#include "emscripten.h"
#include "emscripten/html5.h"
#endif
#include <fcntl.h>

#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#define MIN3(a, b, c) MIN(a, MIN(b, c))
#define MAX3(a, b, c) MAX(a, MAX(b, c))
