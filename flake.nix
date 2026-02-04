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
            # Python 3.11 (kirkstone은 distutils 필요, 3.12+에서 제거됨)
            pkgs.python311
            pkgs.python311Packages.pexpect
            pkgs.python311Packages.setuptools
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

          # 호스트 NixOS PATH 유지 (home은 쓰기 가능하게)
          extraBwrapArgs = [
            "--ro-bind /nix /nix"
            "--bind /home /home"
          ];

          runScript = pkgs.writeShellScript "homeagent-yocto-init" ''
            # FHS 환경 표시 (run.sh에서 체크)
            export HOMEAGENT_FHS=1
            # 호스트 NixOS 도구 PATH 추가 (FHS /usr/bin 우선, 호스트 도구 뒤에)
            export PATH="/usr/bin:/usr/sbin:$PATH:$HOME/.local/bin:/etc/profiles/per-user/$USER/bin"

            echo "============================================"
            echo "  HomeAgent Yocto Build Environment (FHS)"
            echo "============================================"
            echo ""
            echo "Yocto 빌드:"
            echo "  cd yocto"
            echo "  source sources/poky/oe-init-build-env build"
            echo "  bitbake core-image-weston"
            echo ""
            echo "SD 카드 플래싱:"
            echo "  bmaptool copy <image>.wic.bz2 /dev/sdX"
            echo ""
            echo "시리얼 콘솔:"
            echo "  picocom -b 115200 /dev/ttyUSB0"
            echo ""
            echo "Target: Raspberry Pi 5 (scarthgap + Hailo-8/8L)"
            echo "============================================"

            exec bash "$@"
          '';
        };
      in
      {
        packages.default = fhsEnv;

        devShells = {
          # Yocto 빌드 환경 (direnv용 - FHS 진입 안내)
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
              echo "============================================"
              echo "  HomeAgent Yocto Build Environment"
              echo "============================================"
              echo ""
              echo "Yocto 빌드는 FHS 환경이 필요합니다:"
              echo "  nix run"
              echo ""
              echo "개발 환경 (Zig/Go/Flutter):"
              echo "  nix develop .#dev"
              echo "============================================"
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
