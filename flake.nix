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

        # 로컬 nix-environments의 Yocto 환경 가져오기
        yoctoShell = import /home/junghan/repos/3rd/nix-environments/envs/yocto/shell.nix {
          inherit pkgs;
          extraPkgs = with pkgs; [
            bmaptool
            picocom
            ripgrep
            fd
            jq
            tree
            gh
          ];
          shellHookPost = ''
            export HOMEAGENT_FHS=1
            export PATH="$PATH:$HOME/.local/bin:/etc/profiles/per-user/$USER/bin"
            echo ""
            echo "  HomeAgent: RPi5 + Hailo-8/8L (scarthgap)"
            echo "  빌드: cd yocto/build && source ../sources/poky/oe-init-build-env . && bitbake core-image-weston"
            echo ""
          '';
        };
      in
      {
        # nix develop로 FHS 환경 진입
        devShells.default = yoctoShell;

        # 개발용 (Zig/Go/Flutter)
        devShells.dev = pkgs.mkShell {
          name = "homeagent-dev";
          packages = with pkgs; [ zig zls go gopls flutter just ripgrep fd ];
          shellHook = ''echo "HomeAgent Dev Environment"'';
        };
      }
    );
}
