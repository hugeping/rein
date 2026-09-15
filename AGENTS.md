# AGENTS.md

## Project

rein is a minimalist 2D game/demo engine. The `rein` binary is a thin C host (SDL2 + LuaJIT) whose only job is to boot LuaJIT and load `data/core/core.lua`; all engine logic, apps and tools are Lua under `data/`. API docs are in Russian: `doc/api-ru.md`.

## Build

- Deps come from pkg-config: `sdl2` and `luajit` (Alpine: `apk add build-base pkgconf sdl2-dev luajit-dev`).
- `make` → `./rein` (in-tree `src/*.o`; `make clean`).
- SDL3 backend: `make -f Makefile-sdl3` (uses `src/sdl3/platform.c`, needs `sdl3-dev`). It writes the same `./rein`, so always `make clean` when switching backends.
- Makefiles list no header dependencies: after editing any `src/*.h`, run `make clean` before rebuilding.
- `sh make.sh` is a one-shot build.
- SDL3 CI: `contrib/build-rein-sdl3.sh [linux|windows|all]` for static Linux/Windows, `contrib/build-rein-em.sh` for wasm (downloads Lua, needs active emsdk). `.github/workflows/{linux,windows,emscripten}-sdl3.yml` are reusable (`workflow_call`) build workflows; `.github/workflows/release.yml` calls them on push to master/opencode and adds one draft release zip (linux+windows binaries, shared data, `rein-em/`).
- `make PREFIX=/usr/local install` hardcodes runtime data path via `-DDATADIR`.

## Run

- `./rein demo/demo.lua`; bare names resolve to `data/apps/<name>.lua`: `./rein edit|red|irc|sprited|voiced [file]`. No args → `data/boot.lua` launcher menu.
- Options (parsed in `core.lua`): `-s`, `-fs`, `-nosound`, `-vpad`, `--`.
- The binary locates `data/` relative to its own path, not cwd; script paths are relative to cwd.
- Headless smoke test (demos loop forever, so use `timeout`): `timeout 5 env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./rein demo/life.lua`.

## Tests and lint

- Tests are pure LuaJIT — no SDL or `rein` binary needed. Run from the repo root: `sh tests/run.sh`.
- Single file: `luajit tests/run.lua tests/buf_test.lua`. `tests/env.lua` stubs rein globals; `tests/harness.lua` provides `describe`/`it`/`eq`/`ok`/`match`/`fail`.
- Lint the editor modules (config comment in `.luacheckrc`): `luacheck data/apps/red.lua data/lib/red/*.lua`. Pre-existing warnings are expected; don't fix unrelated ones.

## Layout

- `src/main.c` — entrypoint: sets `DATADIR`/`VERSION`/`ARGS`/`PLATFORM`/`SCALE` globals, `require`s `data/core/core.lua`.
- `src/sdl2/platform.c` (SDL2) / `src/sdl3/platform.c` (SDL3) are the only SDL-aware files; everything else uses `src/platform.h`.
- Other C Lua modules: `gfx.c` (`gfx`), `synth.c`, `zvon*.c` (audio), `thread.c`, `net.c`, `system.c` (`sys`), `utf.c`, `bit.c`.
- `data/core/` — engine Lua (main loop, `api`, `font`, `mixer`, `spr`); `data/lib/` — stdlib patches (`std.lua`), editor, sfx, red editor; `data/apps/` — built-in apps.
- Apps run as coroutines driven by `core.run()`; `sys.exec`/suspend/resume powers app switching — see `data/boot.lua`.

## Conventions

- C: tabs, K&R-ish brace style, 79-col-ish wrapping. Lua: 2-space indent, no `local` for rein runtime globals (`screen`, `gfx`, `sys`, `input`, ...).
- `VERSION` is the build date (`date +%y%m%d`) and is shown in the UI/title.
- `GPATH`/`GRTAGS`/`GTAGS` are gitignored gtags indexes; the untracked `zvon-declick*.patch` files and `demo/void.lua` are WIP — don't delete or commit them unasked.
