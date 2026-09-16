# bsp — reproducible SG2000 image build

The core of this repo: build the **full platform image** (bootloader → kernel →
rootfs → freertos) for the SG2000 hub, reproducibly, the same way `yocto/` builds
the RPi5 image. The Zig runtime and applications sit *on top* of this image.

## Model (mirrors `yocto/`)

| Piece | Where | Tracked? |
|-------|-------|----------|
| Build environment (host tools) | `flake.nix` → `packages.buildroot` (FHS) | ✅ committed |
| SDK fork (~5.6G in-tree monorepo) | `bsp/sdk/` cloned by `setup.sh`, pinned to `087547cf8` | ❌ gitignored |
| Our board + Buildroot configs (reproducible SSOT) | `bsp/board/`, `bsp/buildroot/` — `build.sh` injects both | ✅ committed |
| Further customizations (rootfs overlay, patches) | `bsp/board/`, `bsp/patches/` *(as added)* | ✅ committed |

`build.sh` injects our committed outer board config and Buildroot userspace config before
building. Common SDK changes live on `junghan0611/duo-buildroot-sdk-v2` branch
`feat/riscv64-nodejs-pure-cross`; the local patch remains an auditable, fail-closed mirror.
First hub customization: dropped the camera image sensors and MIPI panel (CVITEK vision
middleware is dead weight for a hub).

The fork is based on `milkv-duo/duo-buildroot-sdk-v2` and carries the whole boot chain
(fsbl/opensbi/u-boot/linux_5.10/buildroot/freertos) plus CVITEK libs.
It builds **in-tree** and git-clones a prebuilt toolchain (~840MB) on first build,
so it must be a **writable, pinned working clone** — not vendored, not frozen in nix.

## What this lane is (and is not)

A **fully open, reproducible image for a dev board** — Milk-V Duo S (SG2000). Every layer
(fsbl → opensbi → u-boot → kernel → rootfs → freertos) is built from public sources with a
public SDK, pinned, in a container. No vendor-private repo, no vendor OS.

It is **not** a hub-product image and cannot become one by swapping files: a shipping SG2000
hub like SMHub runs a different OS entirely (mainline ~6.18 kernel, standard
remoteproc/rpmsg + open-amp, RAUC A/B), while this SDK is linux 5.10 with CVITEK's own
`rtos_cmdqu` core-to-core path. Those images are incompatible by construction. Keep the lanes
separate. What actually transfers is the **axis**, not the image: SG2000 SoC, riscv64 ISA,
boot-chain knowledge and cross toolchain. SMHub uses glibc; our image deliberately keeps the
SDK-native musl userspace — a lab where Node/Z2M and `homeagentd`
(`riscv64-linux-musl`) can be built, run and measured on real RISC-V silicon we own.

There is also no MG24 radio on this board, so Zigbee/EZSP work does not happen here.

## ISA: two lanes, one switch

SG2000 carries an ARM Cortex-A53 **and** a RISC-V C906 on one die and boots one or the other.
We build **both** lanes:

- **arm64 / glibc — the Node.js detour** (2026-07-23~). `BR2_aarch64` is a first-class
  architecture for Buildroot's `nodejs` package and riscv64 is not, so this is where the
  Node/Z2M stack stands up without a downstream toolchain fork. It reached flash-and-go in
  v2026.7.24 and stays working — but it is a way around one blocker, **not the destination.**
  **The board in hand is the SMHUB Nano (riscv64)**, so day-to-day work is not here.
- **riscv64 / musl — product lane.** Still the product ISA and the open-ISA thesis. Parked
  while the Node 22 support question sits with upstream (`duo-buildroot-sdk-v2#74`).

Everything above Node — Z2M, image synthesis, flashing, the A2A/A2UI surface — is
ISA-neutral, so returning to RISC-V changes the toolchain and the Node build path, not the
product.

The core is selected by a **physical slide switch** on the board, silkscreened `ARM` and `RV`.
It is a switch, **not an eFuse** — it flips back as many times as you like, nothing is burned
permanently. The image and the switch must agree or nothing boots, and a mismatch looks
exactly like a bricked board. Ground truth is the **first line of the boot log** on the debug
UART (115200):

```text
ARM     B.SCS/0/0.WD.URPL.B.SCS/0/0.WD.URPL.USBI.USBW
RISC-V  C.SCS/0/0.C.SCS/0/0.WD.URPL.USBI.USBW
```

The build log carries the same fact earlier — grep it for `BOOT_CPU=aarch64` or
`BOOT_CPU=riscv` to confirm the lane took before you flash anything.

| Board | ISA / libc | Storage | Flash path |
|-------|-----------|---------|------------|
| `milkv-duos-glibc-arm64-emmc` | arm64 / glibc | eMMC | `usb_dl` in USB recovery mode (see below) — **the Node.js detour, flash-and-go** |
| `milkv-duos-glibc-arm64-sd` | arm64 / glibc | microSD | `dd` the `.img` — eMMC untouched (SD-vs-eMMC boot priority unverified) |
| `milkv-duos-musl-riscv64-sd` | riscv64 / musl | microSD | `dd` the `.img` — reversible, eMMC untouched |
| `milkv-duos-musl-riscv64-emmc` | riscv64 / musl | eMMC | `usb_dl` in USB recovery mode — product lane, parked |

## Use

```bash
./bsp/setup.sh                                   # clone + pin SDK into bsp/sdk/
./bsp/build.sh milkv-duos-glibc-arm64-emmc       # ARM, eMMC       (Node.js detour lane)
./bsp/build.sh milkv-duos-musl-riscv64-sd        # RISC-V, microSD (script default)
./bsp/build.sh milkv-duos-musl-riscv64-emmc      # RISC-V, eMMC
```

Point at an existing local clone (skip re-cloning 5.6G):

```bash
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 ./bsp/build.sh milkv-duos-glibc-arm64-emmc
```

The build runs in the vendor Docker image (`milkvtech/milkv-duo:latest`), so no nix env is
needed. Output lands in `<sdk>/out/` — SD boards produce a dd-able `.img`, eMMC boards an
`upgrade.zip` for `usb_dl`. Confirm the lane took by grepping the log for `BOOT_CPU=`.

Buildroot does **not** rebuild on a defconfig change. When switching lanes or picking up a
board-config change, delete that board's output tree first — a month-stale tree is how the
riscv lane lost a `host-python3` with `_bz2`/`_ssl`/`_hashlib` missing:

```bash
rm -rf <sdk>/buildroot/output/<board> <sdk>/install/soc_sg2000_<board_underscored>
```

## Profiles — one board, two package sets

`HOMEAGENT_BSP_PROFILE` selects what goes *on top of* the BSP. The board, toolchain,
kernel, and `bsp/overlay/common` are identical in both; only the application layer moves.

| Profile | Packages | Overlays | Artifact | Selector |
|---|---|---|---|---|
| `full` (default) | Node 22 + Zigbee2MQTT + mosquitto | `common` + `z2m` | `<board>_<date>.zip` | `flash-emmc.sh arm64` |
| `minimal` | neither (also no ICU) | `common` only | `<board>-minimal_<date>.zip` | `flash-emmc.sh arm64-minimal` |

```bash
# the hub image — unchanged, and still what an unset environment produces
./bsp/build.sh milkv-duos-glibc-arm64-emmc

# same board and BSP, no Node/Z2M
HOMEAGENT_BSP_PROFILE=minimal ./bsp/build.sh milkv-duos-glibc-arm64-emmc
```

**Why it exists: V8 is the whole cost of this image.** On the laptop, 1h16m of a 1h29m
clean build; on gpu1i, 28m37s of 40m (table below). Everything the BSP has to prove —
hostapd, the eMMC-CID stable MAC, `/dev/serial/by-id` — sits *below* Node and does not
need it. `minimal` buys that proof for minutes instead of an hour, which is what makes it
practical to build on a laptop when the remote host is unreachable. Measured clean:
**9m02s on gpu1i, 14m32s on the laptop** (2026-08-30, both hosts, identical artifacts to
within 600 bytes). Quote those and not a faster number you find in a log — a `minimal`
rebuild onto a tree that already has the host tooling finishes in about four minutes, and
that figure has been mistaken for a clean build at least once. It is also the closer
match to what `sks-hub-gecko` flashes: their board runs their firmware, not our Z2M.

**How it is wired.** `bsp/buildroot/<board>_defconfig` *is* the `full` profile. A
non-`full` profile appends `bsp/buildroot/profiles/<board>_<profile>.fragment` to it
inside the container. kconfig keeps the **last** value it reads for a symbol, so the
fragment overrides the base rather than conflicting with it — one base config, so both
profiles can never drift apart on toolchain or BSP. An unknown profile is refused before
the container starts, because the dangerous failure is the silent one: the build succeeds,
the image looks right, and the package set is not what was asked for.

**Three checks stand between a profile and a wrong image**, because a profile can miss in
two different places and only one of them is `.config`:

| when | what it checks | on failure |
|---|---|---|
| before the container | the requested profile has a fragment for this board | refuse |
| before the build | `target/` does not already hold a *previous* profile's rootfs | refuse, and name the tree to delete |
| after the build | both the resolved `.config` **and** `target/` are free of Node/Z2M/mosquitto | move the artifact to `out/quarantine/` |

The middle one exists because `.config` is what the build was *asked for* and `target/` is
what it *produced* — see the profile-switch note under "Rebuilding" below for the day they
disagreed. The last one moves rather than deletes the image: `flash-emmc.sh` picks the
newest glob match, so an unverified image left in `out/` is one command from a board.

**Packages and rootfs files move together.** `bsp/overlay` is split `common/` + `z2m/`
and the fragment drops the `z2m` overlay in the same edit that drops the packages. An
init script for a binary that is not in the image is a boot error, not a leftover.

**The names are a safety rail.** `flash-emmc.sh arm64` globs `<board>_*.zip`, which does
not match `<board>-minimal_*.zip`, so the hub selector can never silently pick up an image
with no Zigbee2MQTT in it. `flash-emmc.sh` also prints a `profile: MINIMAL` banner
whenever the resolved image is one, including when it was given by explicit path.

**Every artifact gets a manifest.** `out/<artifact>.manifest.txt` records the repo commit
(marked `-dirty` if `bsp/` had uncommitted changes), the SDK pin, a sha256, and the
resolved values of the packages that define the profile. An image found in `out/` months
from now can still say what it is.

## Building on a remote host (gpu1i)

A full clean build pins every core for the duration, which is not something to run on a
laptop you want to close. `gpu1i` (16 cores, 61G RAM, NixOS, docker) is the build host; its
home directory differs from the laptop's, so use `~` rather than absolute paths in anything
you script against it. Nothing about the host is special — the point of `setup.sh` +
`build.sh` is that any machine with docker reproduces the same image, and gpu1i is where
that was first demonstrated (2026-07-23) from an empty tree.

**It is worth the round trip — for `full`.** Clean builds, same commit, same path:

| profile | host | total | V8 alone | measured |
|---|---|---|---|---|
| `full` | laptop (17 jobs) | **1h29m** | 1h16m | 2026-07-23, warm `buildroot/dl` |
| `full` | gpu1i (16 cores) | **40m** | 28m37s | 2026-07-23, cold cache |
| `minimal` | laptop (16 cores) | **14m32s** | — | 2026-08-30 |
| `minimal` | gpu1i (16 cores) | **9m02s** | — | 2026-08-30 |

For `full`, same core count buys less than half the wall clock — V8 is the whole story, and
it is bound by single-core throughput more than by job count. A cold `buildroot/dl` did not
close the gap. Budget ~40m on gpu1i, and expect the first ~10m to be download and configure
noise before `nodejs-src ... Building` appears.

For `minimal` the gap nearly closes, because what is left is the kernel and the host
tooling. The round trip is then worth making for a different reason — the remote host frees
the laptop — not because it is dramatically faster.

**Standing it up from scratch** — four commands, ~20 min mostly clone and pull:

```bash
ssh gpu1i 'cd ~/repos/gh/homeagent-config && git pull --rebase origin main'
ssh gpu1i 'docker pull milkvtech/milkv-duo:latest'
ssh gpu1i 'cd ~/repos/gh/homeagent-config && ./bsp/setup.sh'     # clones bsp/sdk, pins it
ssh gpu1i 'cd ~/repos/gh/homeagent-config && tmux new-session -d -s z2m \
  "cd ~/repos/gh/homeagent-config && ./bsp/build.sh milkv-duos-glibc-arm64-emmc \
   > ~/z2m-build.log 2>&1; echo EXIT=\$? >> ~/z2m-build.log"'
```

tmux is what makes it survive the SSH session; `~/z2m-build.log` is the whole record.

**Checking on it.** The SDK pipes through `utils/brmake`, which compresses output, so a
quiet log does not mean a stalled build. Judge by process count, not by log volume:

```bash
ssh gpu1i 'grep EXIT= ~/z2m-build.log'          # present = finished; 0 = success
ssh gpu1i 'tail -3 ~/z2m-build.log'             # current package
ssh gpu1i 'pgrep -c cc1plus'                    # ~16 during V8; 0 means not compiling
ssh gpu1i 'tmux ls'                             # session z2m alive?
ssh gpu1i 'uptime'                              # load ~16 while building
```

V8 is ~70% of the wall clock (28m of gpu1i's 40m) and emits almost nothing through brmake.
Sixteen live `cc1plus` processes is the honest signal that it is working; `cc1plus` dropping
to 0 while the log still says `nodejs-src` means V8 finished and `npm install -g` is next.

**When it fails.** `EXIT=` will be non-zero and the tail names the package. Two rules:

- Do not try to resume by hand into the output tree. Buildroot does not rebuild on a
  defconfig change, and `<pkg>-reinstall` does not re-sync per-package host trees — that
  is exactly how an earlier attempt ended up with `host/bin/npm: No such file or directory`
  while `host-nodejs-bin` sat built one directory over. Delete and rebuild:

  ```bash
  ssh gpu1i 'cd ~/repos/gh/homeagent-config/bsp/sdk && rm -rf \
    buildroot/output/milkv-duos-glibc-arm64-emmc \
    install/soc_sg2000_milkv_duos_glibc_arm64_emmc \
    linux_5.10/build/sg2000_milkv_duos_glibc_arm64_emmc'
  ```

- If the fix is in this repo (defconfig, overlay, patch), commit and push it here first,
  then `git pull --rebase` on gpu1i. `build.sh` injects from the checkout, so an
  uncommitted laptop fix is invisible to the build host.

**Collecting the result.** The board is on the laptop, so flashing happens there:

```bash
ssh gpu1i 'ls -lh ~/repos/gh/homeagent-config/bsp/sdk/out/*.zip'
scp gpu1i:'~/repos/gh/homeagent-config/bsp/sdk/out/milkv-duos-glibc-arm64-emmc_*.zip' \
    ~/repos/3rd/milkv/duo-buildroot-sdk-v2/out/
./bsp/flash-emmc.sh arm64

# minimal is a different name on both ends, on purpose
scp gpu1i:'~/repos/gh/homeagent-config/bsp/sdk/out/milkv-duos-glibc-arm64-emmc-minimal_*.zip*' \
    ~/repos/3rd/milkv/duo-buildroot-sdk-v2/out/
./bsp/flash-emmc.sh arm64-minimal
```

Copy the `.manifest.txt` alongside the zip (the glob above does). An image that travels
between hosts without its manifest is exactly the image nobody can identify later.

Note the two SDK locations are unrelated checkouts of the same pin: gpu1i uses the default
`bsp/sdk`, the laptop uses `~/repos/3rd/milkv/duo-buildroot-sdk-v2` via `HOMEAGENT_BSP_SDK`.
Neither needs to be copied to the other — `host-tools` (6.8G of vendor toolchain) is
committed in the SDK repo, so the pin carries it. Only `buildroot/dl` differs, and that is
just a download cache.

### Rebuilding after an overlay/config change — incremental, ~2-3 min

Once a full build exists on gpu1i, most of our changes touch only `bsp/overlay/` (rootfs
files) — a seed config, an init script — not the package set. Those do **not** need a clean
build. Buildroot rsyncs the overlay in `target-finalize`, which runs on every `make`, and
the eMMC image is repacked from there. The expensive packages (V8, Node) already have their
`.stamp_built` and are not touched.

So the loop is just: push here, pull on gpu1i, rerun `build.sh` against the SAME `bsp/sdk`
output tree (do NOT delete it — that is what makes it incremental):

> **One exception: changing `HOMEAGENT_BSP_PROFILE` is not an incremental rebuild.**
> `output/<board>/target/` is a cumulative tree. Turning a package off stops Buildroot
> installing it; it does not remove what an earlier build already put there. Rebuilding a
> `full` tree as `minimal` therefore produces a minimal `.config` wrapped around a full
> rootfs — and the manifest still reads `minimal`, because every receipt is derived from
> `.config`. Measured 2026-08-30 on gpu1i: a 104M `-minimal_` zip carrying `node` (49.5M),
> `node_modules` (92M) and Zigbee2MQTT, from a run that printed
> `profile verified in .config: BR2_PACKAGE_NODEJS is off`. `build.sh` now refuses this
> before building and names the remedy — `rm -rf <sdk>/buildroot/output/<board>` — and
> asserts on `target/` afterwards, quarantining the artifact if it slips through. Only
> this direction is unsafe; building `full` into a minimal tree just installs Node back.

```bash
# laptop: commit + push the overlay/config change first (build.sh injects from the checkout)
ssh gpu1i 'cd ~/repos/gh/homeagent-config && git pull --rebase origin main'
ssh gpu1i 'cd ~/repos/gh/homeagent-config && tmux new-session -d -s z2m \
  "cd ~/repos/gh/homeagent-config && ./bsp/build.sh milkv-duos-glibc-arm64-emmc \
   > ~/z2m-build.log 2>&1; echo EXIT=\$? >> ~/z2m-build.log"'
```

Measured 2026-07-24, a seed `configuration.yaml` change: **2m37s**, `EXIT=0`, `cc1plus`
stayed at 0 the whole time (V8 never recompiled). Confirm the change actually landed rather
than trusting the timing — grep the produced image:

> **The zip's `rootfs_ext4.emmc` is not a raw ext4 image** — it is CVITEK `CIMG`: a 64-byte
> file header followed by chunks that each carry their own 64-byte header (48 of them in a
> 768M rootfs). Format SSOT: `build/tools/common/image_tool/raw2cimg.py`. `flash-emmc.sh:356`
> already knew this and finds the superblock by its magic rather than assuming an offset;
> what is written down here is the part that was not. That is why the checks here are raw
> string greps and not `debugfs`. **Its failure mode is the dangerous
> part**: `debugfs -R "stat <path>"` returns quietly empty for *every* path, so a probe
> reports the files you want as `MISSING` and the packages you removed as `absent` in the
> same breath — both answers are void, and half of them look like the answer you wanted.
> For file-level checks read `buildroot/output/<board>/target/` instead; it is what went
> into the image, and it is a normal directory.

```bash
ssh gpu1i 'F=$(ls -t ~/repos/gh/homeagent-config/bsp/sdk/out/*.zip | head -1); \
  cd /tmp && unzip -qo "$F" rootfs_ext4.emmc && \
  LC_ALL=C grep -a -o "adapter: ember" rootfs_ext4.emmc | head -1'
```

Clean build is only needed when the package set or a defconfig changes (Buildroot does not
rebuild a package on a defconfig edit — see "When it fails" above). For overlay-only work,
never delete the output tree.

## Flashing eMMC from Linux

```bash
export HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2

HOMEAGENT_BSP_DRYRUN=1 ./bsp/flash-emmc.sh   # resolve image + print ISA contract, touch nothing
./bsp/flash-emmc.sh                          # default lane (HOMEAGENT_BSP_LANE, currently arm64)
./bsp/flash-emmc.sh arm64                    # newest arm64 eMMC image
./bsp/flash-emmc.sh riscv64                  # newest riscv64 eMMC image
./bsp/flash-emmc.sh path/to/image.zip        # explicit image
```

Both ISA lanes are supported. The script resolves the image's ISA from its filename, refuses
anything it cannot classify, and prints the switch position and boot signature that image
requires — it cannot read the switch, so it makes the contract explicit instead. Always
dry-run first; it is the cheapest way to catch a wrong lane before the board is written.

The Duo S eMMC ships **blank**. With no bootable storage the boot ROM falls through to **USB
download mode** and enumerates as `3346:1000 CVITEK USB Com Port` — that is the state you
flash from, no button press needed. A board whose eMMC holds the *other* ISA lands in the same
state for the same reason: it cannot boot, so it falls through.

**Start the script first, then replug the Type-C.** The upstream docs say the ROM
re-enumerates on a timeout loop with the device number climbing. Measured 2026-07-23, it does
not: it enumerates **once per replug**, disconnects about a second later, and then stays
silent. `usb_dl` waits ~90s and times out with `usb device not found` if that single window
already closed — which is exactly what happens if you replug before starting the script.
(If the board boots normally, hold the **recovery button** while plugging in.)

**`cdc_acm` will steal the download interface.** It binds ~186 ms after enumeration and then
libusb cannot claim the interface, so `usb_dl` prints `found usb device vid=0x3346 pid=0x1000`
followed by a bare `[ERR]`. Neither `modprobe -r cdc_acm` (the kernel autoloads it on the next
enumeration) nor an `install cdc_acm /bin/true` drop-in in `/run/modprobe.d` (udev loaded it
anyway) is enough. What works is disabling USB driver autoprobe for the duration:

```bash
echo 0 | sudo tee /sys/bus/usb/drivers_autoprobe   # ... flash ...
echo 1 | sudo tee /sys/bus/usb/drivers_autoprobe
```

`flash-emmc.sh` does this and restores it from an `EXIT` trap. **Restoring promptly matters**:
the board reboots immediately after the download and its NCM gadget enumerates within seconds,
so if autoprobe is still off at that moment the device appears with no interfaces and no
netdev, and only another replug fixes it.

The upstream docs only document a Windows tool, but the SDK ships a Linux `usb_dl`
(`build/tools/common/usb_dl/Linux/`). It is a glibc x86_64 binary, so on NixOS it cannot run
on the host — `flash-emmc.sh` runs it inside the same vendor container the build uses, with
`/dev/bus/usb` passed through, and stages the `usb_dl` + `cv_dl_magic.bin` + `rom/` layout it
expects.

- **Connect the Type-C directly to the host.** Behind a USB hub or dock the ROM's download
  device fails to enumerate (`device descriptor read/64, error -110`, observed).
- **Rollback is always available.** Both lanes' zips live in `<sdk>/out/`; flip the switch and
  reflash the other one.

Success is `[INFO] USB download complete` after ~800 MB of `updated size: N/809230635`. Then
verify — the flash completing is not proof the image boots:

```bash
lsusb | grep 3346                    # 100c = running system, 1000 = still in download mode
ssh root@192.168.42.1                # password: milkv, over the USB network gadget
uname -m                             # aarch64 | riscv64
cat /etc/issue                       # "Welcome to Milk-V DuoS ARM64 eMMC"
```

Wired Ethernet also comes up over DHCP if a cable is plugged in (`eth0`), so the board is
reachable on the LAN as well as on `192.168.42.1`.

## Pin

`setup.sh` pins `junghan0611/duo-buildroot-sdk-v2` branch
`feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). See
[`../runtime/README.md`](../runtime/README.md) for the L0–L4 architecture.

---

## Open debts — measured, not started

`NEXT.md`에서 옮겨 왔다 (2026-09-16). 전부 **조사가 끝났고 착수만 안 한** 것들이라
다음에 이 레인을 열 때 여기부터 읽으면 된다. ⚠️ ION 항목은 **GLG 승인 없이 시작하지 마라.**

- **ION 예약 회수 — Duo S가 지금 148M을 안 쓰고 잡고 있다 (조사 완료, 착수 안 함, 2026-09-01).**
  [측정] `build/boards/cv181x/<board>/memmap.py`의 `ION_SIZE`가 Duo S 170M / Duo 256M 75M이고,
  그 안쪽 예약은 `H26X_BITSTREAM 2M` + `ISP_MEM_BASE 20M`(= `FREERTOS_RESERVED_ION_SIZE` 22M)
  뿐이다. **헤드리스 허브는 ISP도 H.264도 안 쓴다** → assert가 강제하는 바닥 22M까지면
  **Duo S ~148M · Duo 256M ~53M 회수 후보**. 별도로 `BOOTLOGO/FRAMEBUFFER 7.8M`도 디스플레이가
  없으면 미수금이다. **레버 위치**: `memmap.py`는 단일 소스이고 `build/scripts/mmap.mk`가
  `cvi_board_memmap.{h,conf,ld,txt}`를 만들어 u-boot·커널·FreeRTOS 링커가 같이 먹는다 →
  한 파일이 세 층을 움직인다. **다만 `bsp/build.sh`는 지금 `memmap.py`를 주입하지 않는다**
  (defconfig 둘만) → 실작업은 **주입 슬롯 하나 추가**(`bsp/board/<board>/memmap.py`)이지
  포크가 아니다. **미검증 위험 둘**: cvi 멀티미디어 드라이버가 들어있는 채로 ION만 줄이면 부팅
  실패 가능(드라이버 제거와 짝) · `BOOTLOGO`는 u-boot 로고 경로가 참조. 상세 =
  `docs/TARGET_DEVICE.md` "레버 — ION은 카메라 몫이고" 절. **GLG 승인 없이 시작하지 마라.**

- **Duo S 온보드 버튼으로는 런타임 팩토리리셋을 못 묶는다 — 조사 완료, 보류 (2026-08-30).** GLG가 다시 볼 예정이라 `docs/DUO-S-BUTTONS.md`에 따로 남겼다. 요지: 이 이미지엔 `gpio-keys` 노드도 `CONFIG_KEYBOARD_GPIO`도 없어 **어떤 버튼도 이벤트를 못 낸다**(벽 1), 그리고 RST는 하드웨어 리셋·RECOVERY는 BootROM이 전원 인가 시점에 읽는 스트랩이라 런타임 입력이 아니다(벽 2). SoC의 전용 파워버튼 핀 `PWR_BUTTON1`은 Duo S에서 이더넷 속도 LED로 가 있다(`cvi_board_init.c:59`, 4개 변종 전부). 재개하면 **fork 핀 축이라 위 커널 defconfig 주석 빚과 한 번에 묶는 게 싸다**.

- **커널 defconfig 주석이 틀렸다 — 이미지엔 무해 (2026-07-24 fork 실물 확인).** `build/boards/cv181x/sg2000_milkv_duos_glibc_arm64_emmc/linux/cvitek_..._defconfig` 203번 설명주석이 "ZBDongle-E (CH9102F) → CDC-ACM"인데 **실측은 CP210x**(ttyUSB0). **심볼은 전부 맞다** (`USB_ACM=y`·`USB_SERIAL_CP210X=y`·`CH341=y`·`FTDI_SIO=y`) — 거짓인 건 순수 `#` 주석뿐. kconfig가 주석을 무시하므로 고쳐도 **이미지는 바이트 불변 → 실기 검증 불필요**. fork에서 주석만 정정하고 `setup.sh`의 `SDK_COMMIT` pin만 올리면 끝. (이전 NEXT의 "실기 검증이 끝난 뒤에"는 과한 신중함이었다.)
- **corepack은 이미지에 남지만 의도적 유지 (2026-07-24 GLG 판단).** `--without-corepack`이 patch 0002의 `ifeq ($(BR2_RISCV_64),y)` 분기 안에만 있어 arm 레인엔 안 걸리고, corepack 1.2MB가 이미지에 남는다. 원래 "닫을 빚"으로 적었으나 **아직 개발 중이라 corepack이 필요하고 급하지 않으므로 지금은 닫지 않는다.** 제품화 단계에서 재판정(그때 patch 0002의 해당 3줄을 `ifeq/else` 분기 **밖**으로 옮기면 양 레인 공통 적용).
- **`/proc/cmdline`에 `earlycon=sbi riscv.fwsz=0x80000`**가 aarch64 커널에 그대로 남아 있다. 무해하지만 SDK cmdline 템플릿이 레인별로 분리돼 있지 않다는 뜻이다.
- **`bsp/overlay`가 arm64 defconfig에만 연결돼 있다.** riscv 레인 복귀 시 같은 overlay를 붙일지 결정해야 한다.
- **MemTotal 311MB / 512MB**, rootfs 235MB/768MB(Z2M 91MB 추가 전). hub-minimal에서 회수 여지를 안 봤다.
- **Z2M 상태 백업 — 스킬엔 있고 스크립트엔 없다 (2026-07-24 검수로 정정).** `/var/lib/zigbee2mqtt`에 device DB와 **네트워크 키**가 있어 **reflash하면 날아간다**(전 기기 재페어링). `duo-s-flash` 스킬 §7이 이미 백업 한 줄(`ssh root@192.168.42.1 'tar cz -C /var/lib zigbee2mqtt' > …`)을 담고 있다 — 없는 건 `flash-emmc.sh`/README 쪽이다. flash 직전에 자동화/강제할지만 판단하면 된다. 청사진 참고: SMHub 매뉴얼도 OTBR reflash 시 Thread 데이터 소실을 백업 절차와 함께 명시한다(`docs/smhub-manual/pages/17-*`).
