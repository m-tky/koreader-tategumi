# Unit Tests

Unit tests are written for [busted](https://lunarmodules.github.io/busted/)
(a version is automatically provided by the build system), and executed in
parallel with the meson test runner.

You can run them with `./kodev test`, examples:

- to run all tests (frontend & base): `./kodev test`
- frontend only: `./kodev test front`
- to run one specific base test: `./kodev test base util`
- to list available tests: `./kodev test -l`

Check the output of `./kodev test -h` for the full usage.

## Nix Flakes Development Environment

A `flake.nix` file is provided at the project root for setting up a development environment with all required dependencies.

### Entering the dev shell

```bash
nix develop
```

This provides a shell with:
- Build toolchain: gcc, cmake, ninja, meson, autoconf, automake, libtool
- Libraries: SDL3, libGL, libusb1, ImageMagick
- Lua: LuaJIT, luarocks, busted (test framework)
- Code quality tools: luacheck, shellcheck, shfmt

### Available aliases

Once in the dev shell, the following aliases are available:

```bash
koreader-build          # Build emulator (make -C base)
koreader-run            # Run emulator (make -C base run)
koreader-test-base      # Run base/ unit tests
koreader-test-front     # Run frontend unit tests
koreader-test-vertical  # Run vertical text screenshot tests
koreader-create-epub    # Create test EPUB fixture
```

### Setting up Lua test dependencies

Before running tests, install Lua test rocks into the KOReader build tree:

```bash
nix develop .#setup-luarocks
```

This installs busted and dependencies into `base/build/*/luarocks/`. After setup, set the following environment variables before running busted directly:

```bash
export LUA_PATH="/path/to/base/build/*/luarocks/share/lua/5.1/?.lua;/path/to/base/build/*/luarocks/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="/path/to/base/build/*/luarocks/lib/lua/5.1/?.so;;"
```

### Running tests outside nix shell

For running tests without entering the nix shell, copy the required Lua modules from the nix store:

```bash
# Copy busted
cp -r /nix/store/*-luajit2.1-busted-*/share/lua/5.1/* base/spec/rocks/share/lua/5.1/

# Copy luasystem
cp /nix/store/*-luajit2.1-luasystem-*/lib/lua/5.1/system/core.so base/spec/rocks/lib/lua/5.1/system.so

# Copy luafilesystem
cp /nix/store/*-luajit2.1-luafilesystem-*/lib/lua/5.1/lfs.so base/spec/rocks/lib/lua/5.1/

# Make files writable
chmod -R +w base/spec/rocks
```

Then run tests from the base directory:
```bash
cd base
./test-runner/runtests spec/unit
```

### Headless testing

For CI or headless environments, set the SDL video driver to dummy:

```bash
SDL_VIDEODRIVER=dummy ./kodev test
```

## Focused vertical regressions

After rebuilding the native renderer for any C++ changes, run the cascade and
navigation regressions against that build (the `-b` flag skips rebuilding):

```sh
SDL_VIDEODRIVER=dummy ./kodev test -b front vertical_logical_cascade reader_vertical_navigation
```

The cascade spec checks observable character-box geometry with shared baselines:
writing-mode order/inheritance, inline styles, physical/logical precedence and
importance, targeted margin/border sides, horizontal mode changes, and generated
content. The navigation spec keeps distinct reopen tests for explicit LTR and an
explicit RTL choice matching the automatic direction, as well as mixed-page
selection and initial-page restoration checks.

## Standalone native render helpers

Run the isolated CRengine buffer, CSS cascade, and table-edge regressions without building
KOReader or downloading dependencies. With only the parent repository checked
out, initialize these two gitlinks (do not initialize all submodules recursively):

```sh
git submodule update --init --depth 1 base
git -C base submodule update --init --depth 1 thirdparty/kpvcrlib/crengine
CXX=g++ base/thirdparty/kpvcrlib/crengine/tests/run-fork-render-helpers.sh
```

Use a Linux host C++17 compiler with AddressSanitizer and UndefinedBehaviorSanitizer
support, or run the last command inside `nix develop`. The script compiles in a
temporary directory and removes it on exit. The **Native render helpers** GitHub
Actions workflow runs this command automatically for changes to the `base`
gitlink or the workflow itself; it does not fetch unrelated recursive dependencies
or build the reader. Only the standalone helper test is sanitizer-instrumented,
not the full engine or frontend rendering tests.

Coverage includes rotation-buffer row preservation, zero-filled growth and
no-growth reuse; transient CSS cascade flags across axis changes and replay;
table adjacency with spans; overlapping intervals requiring prefix maxima; and
original-order border ties. These are correctness tests, not an actual rendering
performance benchmark or a measured speedup claim. They do not replace the
frontend rendering tests above.
