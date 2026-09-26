# Repository Guidelines

## Project Overview

KOReader is an e-book reader for e-ink devices. This repository is the `m-tky/koreader-tategumi` soft fork, focused on Japanese EPUB vertical-rl (縦書き) rendering and right-to-left manga page order. It tracks upstream KOReader. Keep changes small and easy to rebase: minimize edits to upstream/original files, and put fork-specific behavior in separate files where practical.

## Architecture & Data Flow

`reader.lua` initializes LuaJIT, settings, localization, and device state, then starts the reader or file manager. The Lua frontend owns application/UI behavior: `frontend/apps/reader/readerui.lua` composes reader modules, while `frontend/ui/uimanager.lua` handles the event loop, input, window stack, and repaint scheduling.

Documents are exposed through provider modules in `frontend/document/`. `CreDocument` initializes and adapts the native crengine document API. The native pipeline in `base/thirdparty/kpvcrlib/crengine/crengine/` parses DOM and styles, lays out blocks/text, paginates, and draws. `base/cre.cpp` bridges Lua and crengine. High-level flow: reader UI → document provider / CRE bridge → crengine DOM, layout and page view → drawing back to the frontend.

Vertical layout deliberately reuses the horizontal pipeline with swapped X/Y roles. Keep vertical-only behavior in compact `_vert` helpers and hooks where established. Key areas: `lvlogical.h` (logical properties), `lvrend.cpp` (block layout), `lvtextfm.cpp` and `lvtextfm_vert.cpp` (inline layout/drawing), `lvfntman.cpp` and `lvfntman_vert.cpp` (shaping and JLReq/JFM typography), and `lvdocview.cpp` (view coordinates). Consult the fork-specific vertical notes in this file and the regression specs before changing these paths.

## Key Directories

- `frontend/`: Lua application, reader, documents, UI, devices, and plugins.
- `base/`: native engine bridge, build system, and the crengine submodule.
- `spec/`: frontend Busted specs and shared fixtures/helpers.
- `base/spec/`, `base/tests/`: native/base tests and fixtures.
- `doc/`: build, development, and testing references.
- `platform/`, `make/`: device/platform integration and build configuration.
- `scripts/`, `tools/`: repository workflows, development utilities, and release tooling.
- `test/fixtures/vertical_text/`: vertical-rendering EPUB fixtures.

## Development Commands

Prefer the Nix development shell for a consistent toolchain. Install test rocks once after a build when required: `nix develop .#setup-luarocks`.

```sh
nix develop --command ./kodev build -d emulator
nix develop --command ./kodev run emulator
nix develop --command ./kodev test front
nix develop --command ./kodev test base
nix develop --command make -j1 testfront
nix develop --command ./kodev test front -f "Vertical text"
nix develop --command ./kodev check
```

`./kodev` is the normal entry point for build, run, test, and check tasks; it selects targets and delegates to Make. The emulator is the default target. For headless test runs, set `SDL_VIDEODRIVER=dummy`. See `doc/Building.md`, `doc/Unit_tests.md`, and `kodev` help for platform-specific requirements and options. `./kodev wbuilder` launches a lightweight UI-widget development harness.

## Code Conventions & Common Patterns

- Preserve upstream style. As a soft fork, keep changes minimal and easy to rebase: avoid modifying upstream/original files unless necessary; isolate fork-specific code in separate files when practical, and keep unavoidable upstream-file changes small and clearly localized. Avoid unrelated cleanup.
- Write code, comments, commit messages, and project documentation in English.
- Frontend code is Lua/LuaJIT, organized as modules and object composition; follow neighboring module APIs and lifecycle patterns. Keep document access behind the existing document-provider interfaces.
- Native renderer changes belong in the existing crengine pipeline; avoid duplicating upstream behavior when a small vertical-mode hook suffices.
- Follow `.editorconfig`: four-space indentation by default, two spaces in Markdown and selected web files, tabs in Makefiles; LF, UTF-8, final newline.
- Use `logger.dbg` for temporary Lua diagnostics; its arguments are evaluated even when debug output is off, so guard expensive work. Remove ad-hoc debug prints such as `fprintf(stderr, ...)` before completion. Existing vertical diagnostic counters used by specs are allowed; do not add ad-hoc counters.
- For rendering geometry, confirm behavior with runtime logs rather than screenshot pixel measurements.

## Important Files

- `reader.lua`: application bootstrap and startup dispatch.
- `frontend/apps/reader/readerui.lua`, `frontend/ui/uimanager.lua`: reader composition and UI event loop.
- `frontend/document/credocument.lua`, `base/cre.cpp`: Lua/native document boundary.
- `base/thirdparty/kpvcrlib/crengine/crengine/src/`: native DOM, layout, font, and view implementation.
- `kodev`, `Makefile`, `flake.nix`: developer CLI, build targets, and Nix environment.
- `AGENTS.md`: repository architecture, development commands, and fork-specific contribution guidance.

## Runtime/Tooling Preferences

The frontend runs on LuaJIT; native components use C/C++ (C11/C++17 toolchains). Do not assume Node or Bun is part of the project runtime. Nix provides LuaJIT, Busted, build tools, and optional lint utilities. The expected host toolchain and platform requirements are documented in `doc/Building.md` and `doc/Building_targets.md`.

This is a nested submodule chain: top-level KOReader → `base` (koreader-base) → `base/thirdparty/kpvcrlib/crengine` (crengine). Do not publish a parent pointer to a child commit unavailable from the child repository's default branch; CI fetches submodules by SHA. For C++ changes, use `scripts/push-chain.sh` to preview or push the chain; its `--dry-run` may still fetch remote refs.

## Testing & QA

Frontend and base unit tests are Lua specs using Busted, normally scheduled through Meson by the test runner. Put frontend specs under `spec/unit/`; use shared initialization/helpers and fixtures rather than ad-hoc setup. Prefer focused coverage of consumer-visible behavior and use the relevant existing vertical regression specs when changing layout, glyph shaping, coordinates, ruby, or image wrapping.

```sh
./kodev test -l                         # list suites/specs
./kodev test front -f "Vertical text"  # focused vertical specs
./kodev test front                      # frontend suite
./kodev test base                       # base suite
./kodev check                           # repository checks (ShellCheck, Lua checks, etc.)
```

For vertical rendering changes, the primary no-ruby fixture is `spec/front/unit/data/fixtures/vertical_text/simple_ja_noruby.epub`; ruby and feature-specific fixtures live alongside related specs and in `test/fixtures/vertical_text/`. A headless screenshot/dictionary QA helper is `test/test-vertical.sh`; use runtime logs to assess geometry. Static checks are separate from tests and optional tools may be unavailable outside the Nix shell.
