{
  description = "HomeAgent Config - RPi5 Yocto Build Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-environments.url = "github:nix-community/nix-environments";
  };

  outputs = { self, nixpkgs, nix-environments }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system} = {
        # Yocto 빌드 환경 (FHS 격리)
        default = nix-environments.devShells.${system}.yocto.overrideAttrs (old: {
          name = "homeagent-yocto";

          # 추가 패키지
          buildInputs = (old.buildInputs or []) ++ [
            pkgs.git
            pkgs.git-lfs
            pkgs.repo  # Android repo tool (선택적)
            pkgs.bmaptool  # SD 카드 플래싱
            pkgs.picocom  # 시리얼 콘솔
          ];

          shellHook = (old.shellHook or "") + ''
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
            echo "        meta-clang, meta-flutter-sony"
            echo "============================================"
          '';
        });

        # 개발용 (Zig/Go/Flutter)
        dev = pkgs.mkShell {
          name = "homeagent-dev";

          buildInputs = with pkgs; [
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
    };
}
