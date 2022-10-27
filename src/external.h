#ifdef _WIN32
 #include <windows.h>
#else
 #include <unistd.h>
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
