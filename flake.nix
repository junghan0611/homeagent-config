{
  description = "HomeAgent Config - RPi5 Yocto Build Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # lz4c 래퍼 스크립트 (Yocto가 lz4c를 요구함)
        # FHS 환경에서 /usr/bin/lz4를 호출
        lz4cWrapper = pkgs.writeShellScriptBin "lz4c" ''
          exec /usr/bin/lz4 "$@"
        '';

        # Yocto FHS 환경
        fhsEnv = pkgs.buildFHSEnv {
          name = "homeagent-yocto";

          targetPkgs = pkgs: [
            # Yocto 필수 HOSTTOOLS
            pkgs.chrpath
            pkgs.diffstat
            pkgs.lz4
            lz4cWrapper       # lz4c 심볼릭 링크
            pkgs.rpcsvc-proto # rpcgen

            # 빌드 도구
            pkgs.gnumake
            pkgs.gcc
            pkgs.binutils
            pkgs.patch
            pkgs.perl
            pkgs.python3
            pkgs.python3Packages.pexpect
            pkgs.cpio
            pkgs.unzip
            pkgs.bzip2
            pkgs.gzip
            pkgs.xz
            pkgs.zstd
            pkgs.wget
            pkgs.curl
            pkgs.file
            pkgs.which

            # Git
            pkgs.git
            pkgs.git-lfs

            # 추가 유틸
            pkgs.ncurses      # menuconfig
            pkgs.texinfo
            pkgs.socat        # devshell
            pkgs.tmux
            pkgs.screen

            # SD 카드 플래싱
            pkgs.bmaptool
            pkgs.picocom      # 시리얼 콘솔

            # 개발 도구
            pkgs.ripgrep
            pkgs.fd
            pkgs.jq
            pkgs.tree

            # GitHub CLI
            pkgs.gh
          ];

          multiPkgs = pkgs: [ pkgs.zlib ];

          runScript = pkgs.writeShellScript "homeagent-yocto-init" ''
            echo "============================================"
            echo "  HomeAgent Yocto Build Environment"
            echo "============================================"
            echo ""
            echo "Quick Start:"
            echo "  1. cd yocto/sources && ./setup-layers.sh"
            echo "  2. source poky/oe-init-build-env ../build"
            echo "  3. bitbake core-image-weston"
            echo ""
            echo "Target: Raspberry Pi 5"
            echo "Layers: poky, meta-raspberrypi, meta-openembedded,"
            echo "        meta-clang"
            echo "============================================"

            exec bash "$@"
          '';
        };
      in
      {
        packages.default = fhsEnv;

        devShells = {
          # Yocto 빌드 환경 (FHS 격리)
          default = pkgs.mkShell {
            name = "homeagent-yocto";

            packages = with pkgs; [
              git
              git-lfs
              bmaptool
              picocom
              ripgrep
              fd
              gh
            ];

            shellHook = ''
              if [[ -z "$IN_HOMEAGENT_FHS" ]]; then
                export IN_HOMEAGENT_FHS=1
                exec ${fhsEnv}/bin/homeagent-yocto
              fi
            '';
          };

          # 개발용 (Zig/Go/Flutter)
          dev = pkgs.mkShell {
            name = "homeagent-dev";

            packages = with pkgs; [
              # Zig
              zig
              zls

              # Go
              go
              gopls

              # Flutter (호스트 개발용)
              flutter

              # Tools
              just
              ripgrep
              fd
            ];

            shellHook = ''
              echo "HomeAgent Dev Environment (Zig/Go/Flutter)"
            '';
          };
        };
      }
    );
}
