{
  description = "KOReader base (crengine) development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        luarocksPackages = [
          "busted"
          "luacov"
          "cluacov"
          "luafilesystem"
          "luassert"
          "luasystem"
          "penlight"
          "say"
          "mediator_lua"
          "lua-term"
          "lua_cliargs"
        ];

        koreaderBuild = pkgs.writeShellScriptBin "koreader-build" ''
          exec make -C base "$@"
        '';
        koreaderRun = pkgs.writeShellScriptBin "koreader-run" ''
          make

          install_dir="$(
            make -s --no-print-directory \
              PHONY+=__print_install_dir \
              --eval='__print_install_dir:;@printf "%s\\n" "$(INSTALL_DIR)"' \
              __print_install_dir
          )"
          cd "$install_dir/koreader"

          while true; do
            status=0
            ./luajit reader.lua "$@" || status=$?
            [ "$status" -eq 85 ] || exit "$status"
            set --
          done
        '';
        koreaderTestBase = pkgs.writeShellScriptBin "koreader-test-base" ''
          exec base/test-runner/runtests "$@"
        '';
        koreaderTestFront = pkgs.writeShellScriptBin "koreader-test-front" ''
          exec make testfront "$@"
        '';
        koreaderTestVertical = pkgs.writeShellScriptBin "koreader-test-vertical" ''
          exec test/test-vertical.sh "$@"
        '';
        koreaderScreenshotCompare = pkgs.writeShellScriptBin "koreader-screenshot-compare" ''
          exec test/test-vertical.sh compare "$@"
        '';
        koreaderCreateEpub = pkgs.writeShellScriptBin "koreader-create-epub" ''
          exec python3 base/tests/fixtures/vertical_text/create-epub.py \
            base/tests/fixtures/vertical_text/simple_ja_noruby.epub "$@"
        '';

        linuxRuntimeLibraries = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.libGL
          pkgs.libusb1
        ];
        linuxLibraryPathHook = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          export LD_LIBRARY_PATH="${pkgs.sdl3}/lib:${pkgs.libGL}/lib:${pkgs.libusb1}/lib:$LD_LIBRARY_PATH"
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            gcc gnumake cmake ninja meson pkg-config autoconf automake libtool nasm
            git gnupatch wget unzip p7zip gettext
            python3 perl
            sdl3
          ] ++ linuxRuntimeLibraries ++ [
            imagemagick
            luajit luarocks
            luajitPackages.busted
            luajitPackages.luassert
            luajitPackages.say
            luajitPackages.mediator_lua
            luajitPackages.luafilesystem
            luajitPackages.penlight
            luajitPackages.luacov
            ccache
            luajitPackages.luacheck
            shellcheck shfmt
            zip
            koreaderBuild koreaderRun koreaderTestBase koreaderTestFront
            koreaderTestVertical koreaderScreenshotCompare koreaderCreateEpub
            # CI lint tools (crengine/.github/workflows/build.yml runs clang-tidy + cppcheck)
            clang-tools cppcheck
            # System libs needed for crengine lint to resolve includes via pkg-config
            harfbuzz freetype fribidi libunibreak libutf8proc
            # LuaTeX-ja reference renderer for vertical-rl visual comparison
            # (used during JFM development to verify output matches LuaTeX-ja).
            (texlive.combine {
              inherit (texlive) scheme-basic luatexja fontspec luaotfload xkeyval lualatex-math luatex
                                jlreq everyhook filehook
                                ifmtarg framed cmap zref
                                pdftexcmds infwarerr kvoptions epstopdf-pkg
                                svn-prov koma-script trimspaces etoolbox xstring;
            })
          ];

          shellHook = ''
            ${linuxLibraryPathHook}

            echo "KOReader dev shell ready."
            echo "  koreader-build          — build emulator (make -C base)"
            echo "  koreader-run            — run emulator (make run)"
            echo "  koreader-test-base      — run base/ unit tests"
            echo "  koreader-test-front     — run frontend unit tests"
            echo "  koreader-test-vertical  — run vertical text screenshot tests"
            echo "  koreader-create-epub    — create test EPUB fixture"
            echo ""
            echo "Before first test run, install Lua test rocks:"
            echo "  nix develop .#setup-luarocks"
          '';
        };

        devShells.setup-luarocks = pkgs.mkShell {
          packages = with pkgs; [
            gcc gnumake cmake ninja meson pkg-config autoconf automake libtool nasm
            git gnupatch wget unzip gettext python3 perl
            sdl3 imagemagick
          ] ++ linuxRuntimeLibraries ++ [
            luajit luarocks ccache zip shellcheck shfmt
          ];

          shellHook =
            let
              installCmds = pkgs.lib.concatMapStringsSep "\n" (pkg:
                "  luarocks install ${pkg} --tree=\"$BUILDDIR/luarocks\" --lua-dir=\"$BUILDDIR\" || echo 'WARNING: luarocks install ${pkg} failed'"
              ) luarocksPackages;
            in
            ''
              ${linuxLibraryPathHook}

              BUILDDIR="$(ls -d base/build/*-debug 2>/dev/null | head -1)"
              if [ -z "$BUILDDIR" ]; then
                echo "ERROR: No build directory found. Build KOReader first:"
                echo "  make -C base"
                exit 1
              fi

              echo "Installing Lua test rocks into KOReader build tree..."
              echo "Build dir: $BUILDDIR"
              echo ""

              if [ ! -f "$BUILDDIR/luajit" ]; then
                echo "ERROR: KOReader LuaJIT not found at $BUILDDIR/luajit"
                echo "Build KOReader first: make -C base"
                exit 1
              fi

              ${installCmds}

              echo ""
              echo "Lua test rocks installed."
              echo ""
              echo "Set these before running busted:"
              echo "  export LUA_PATH=\"$BUILDDIR/luarocks/share/lua/5.1/?.lua;$BUILDDIR/luarocks/share/lua/5.1/?/init.lua;;\""
              echo "  export LUA_CPATH=\"$BUILDDIR/luarocks/lib/lua/5.1/?.so;;\""
              exit 0
            '';
        };

      }
    );
}
