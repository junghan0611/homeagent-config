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
        inherit (pkgs) lib;

        # Yocto HOSTTOOLS용 ncurses (termlib 포함)
        ncurses' = pkgs.ncurses5.overrideAttrs (old: {
          configureFlags = old.configureFlags ++ [ "--with-termlib" ];
          postFixup = "";
        });

        # lz4c 심볼릭 링크 (Yocto HOSTTOOLS 요구)
        lz4' = pkgs.lz4.overrideAttrs (old: {
          postInstall = ''
            ln -rs $out/bin/lz4 $out/bin/lz4c
          '';
        });

        # Bitbake 환경 변수 설정 (nix-environments/yocto 동등)
        nixconf =
          let
            setVars = { "NIX_DONT_SET_RPATH" = "1"; };
            exportVars = [
              "LOCALE_ARCHIVE"
              "NIX_CC_WRAPPER_TARGET_HOST_${pkgs.stdenv.cc.suffixSalt}"
              "NIX_CFLAGS_COMPILE"
              "NIX_CFLAGS_LINK"
              "NIX_LDFLAGS"
              "NIX_DYNAMIC_LINKER_${pkgs.stdenv.cc.suffixSalt}"
            ];
            exports =
              (builtins.attrValues (builtins.mapAttrs (n: v: "export ${n}=\"${v}\"") setVars)) ++
              (builtins.map (v: "export ${v}") exportVars);
            passthroughVars = (builtins.attrNames setVars) ++ exportVars;
          in
          {
            conf = pkgs.writeText "nixvars.conf" ''
              ${lib.strings.concatStringsSep "\n" exports}
              BB_BASEHASH_IGNORE_VARS += "${lib.strings.concatStringsSep " " passthroughVars}"
            '';
            inherit passthroughVars;
          };

        # Yocto FHS 환경 (sks-hub 패턴: buildFHSEnv + runScript)
        yoctoFhs = pkgs.buildFHSEnv {
          name = "homeagent-yocto";

          targetPkgs = pkgs: with pkgs; [
            # Yocto 필수 빌드 도구 (nix-environments/yocto 동등)
            attr bc binutils bzip2 chrpath cpio diffstat expect file
            gcc gdb git gnumake hostname kconfig-frontends
            libxcrypt libxcrypt-legacy lz4' ncurses'
            (ncurses'.override { unicodeSupport = false; })
            openssh patch perl
            (python3.withPackages (ps: [ ps.setuptools ps.pyaml ps.websockets ]))
            rpcsvc-proto unzip util-linux wget which xz zlib zstd
            bison flex pkg-config
            # X11 (bitbake 일부 레시피)
            xorg.libX11 xorg.libXext xorg.libXrender
            xorg.libXi xorg.libXtst xorg.libxcb
            # HomeAgent 추가 도구
            bmaptool picocom minicom lrzsz
            python3Packages.pyspinel  # OpenThread NCP/RCP
            ripgrep fd jq tree gh
          ];

          multiPkgs = pkgs: [ ];

          runScript = pkgs.writeShellScript "homeagent-yocto-init" ''
            # Yocto 빌드 환경 변수 (nix-environments/yocto profile 동등)
            unset LD_LIBRARY_PATH

            export NIX_DYNAMIC_LINKER_${pkgs.stdenv.cc.suffixSalt}=${
              if pkgs.stdenv.isx86_64 then "/lib/ld-linux-x86-64.so.2"
              else if pkgs.stdenv.isAarch64 then "/lib/ld-linux-aarch64.so.1"
              else throw "Unsupported architecture"
            }

            export BB_ENV_PASSTHROUGH_ADDITIONS="${lib.strings.concatStringsSep " " nixconf.passthroughVars}"
            export BBPOSTCONF="${nixconf.conf}"

            # HomeAgent 환경
            export HOMEAGENT_FHS=1
            export PATH="$PATH:$HOME/.local/bin:/etc/profiles/per-user/$USER/bin"

            echo ""
            echo "  HomeAgent: RPi5 + Hailo-8/8L (scarthgap)"
            echo "  빌드: ./run.sh bb  |  devtool: ./run.sh npm-shrinkwrap <pkg>"
            echo ""

            exec bash "$@"
          '';
        };
      in
      {
        # Yocto FHS 패키지 (nix build으로 빌드 가능)
        packages.yocto = yoctoFhs;

        # nix develop → mkShell shellHook에서 FHS로 exec
        devShells.default = pkgs.mkShell {
          name = "homeagent-yocto";
          shellHook = ''
            if [[ -z "$HOMEAGENT_FHS" ]]; then
              export HOMEAGENT_FHS=1
              exec ${yoctoFhs}/bin/homeagent-yocto
            fi
          '';
        };

        # 개발용 (Go + Node.js + Flutter)
        devShells.dev = pkgs.mkShell {
          name = "homeagent-dev";
          packages = with pkgs; [
            go gopls          # Go 컨트롤러
            nodejs_22         # matter.js / z2m 개발
            flutter           # 크로스플랫폼 앱 (Linux + Android)
            just              # 태스크 러너
            ripgrep fd        # 검색
          ];
          shellHook = ''
            echo "HomeAgent Dev: Go $(go version | cut -d' ' -f3) / Node $(node -v) / Flutter $(flutter --version --machine 2>/dev/null | grep -o '"frameworkVersion":"[^"]*"' | cut -d'"' -f4)"
          '';
        };
      }
    );
}
