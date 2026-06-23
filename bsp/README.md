# bsp — reproducible SG2000 image build

The core of this repo: build the **full platform image** (bootloader → kernel →
rootfs → freertos) for the SG2000 hub, reproducibly, the same way `yocto/` builds
the RPi5 image. The Zig runtime and applications sit *on top* of this image.

## Model (mirrors `yocto/`)

| Piece | Where | Tracked? |
|-------|-------|----------|
| Build environment (host tools) | `flake.nix` → `packages.buildroot` (FHS) | ✅ committed |
| Upstream SDK (~5.6G in-tree monorepo) | `bsp/sdk/` cloned by `setup.sh`, pinned | ❌ gitignored |
| Our board config (the reproducible SSOT) | `bsp/board/<board>/defconfig` — `build.sh` injects onto the SDK before build | ✅ committed |
| Further customizations (rootfs overlay, patches) | `bsp/board/`, `bsp/patches/` *(as added)* | ✅ committed |

`build.sh` copies our committed `bsp/board/<board>/defconfig` over the SDK's stock
defconfig at build time — so the upstream clone stays pristine and our changes are
the only tracked config. First hub customization: dropped the camera image sensors
and MIPI panel (CVITEK vision middleware is dead weight for a hub).

The upstream `milkv-duo/duo-buildroot-sdk-v2` is a single tree carrying the whole
boot chain (fsbl/opensbi/u-boot/linux_5.10/buildroot/freertos) plus CVITEK libs.
It builds **in-tree** and git-clones a prebuilt toolchain (~840MB) on first build,
so it must be a **writable, pinned working clone** — not vendored, not frozen in nix.

## Use

```bash
./bsp/setup.sh                                   # clone + pin SDK into bsp/sdk/
nix develop .#buildroot                          # enter FHS build env
./bsp/build.sh milkv-duos-glibc-arm64-emmc       # build ARM A53 eMMC image
# one-shot:
nix run .#buildroot -- -c "./bsp/build.sh milkv-duos-glibc-arm64-emmc"
```

Point at an existing local clone (skip re-cloning 5.6G):

```bash
HOMEAGENT_BSP_SDK=/path/to/duo-buildroot-sdk-v2 ./bsp/build.sh <board>
```

Output images land in `<sdk>/out/`.

## Pin

`setup.sh` pins `develop` @ `ad920f839`. Board: **ARM A53 boot** (`milkv-duos-glibc-arm64-{emmc,sd}`).
Verify the SoC boots as ARM (not RISC-V) via the boot log first char `B`. See
[`../runtime/README.md`](../runtime/README.md) for the L0–L4 architecture.
