---
name: duo-s-flash
description: "Milk-V Duo S(SG2000) eMMC를 USB recovery로 굽는 자리. 몇 달에 한 번 하는 일이라 매번 같은 삽질을 반복하게 되는 절차를 시퀀스로 고정한다: 슬라이드 스위치 ISA 계약, 스크립트 먼저-케이블 나중, cdc_acm을 '막는 게 아니라 붙였다 떼는' 순서, 그리고 다섯 가지 실패 문자열의 구분. 특히 usb_dl이 100%와 'USB download complete'를 찍고도 한 바이트도 안 쓰는 거짓 완료 모드와, 그걸 ext4 UUID로 증명하는 법을 담는다. 트리거: 'duo flash', 'duo-s 퓨징', 'eMMC 굽기', 'usb_dl', 'flash-emmc.sh', 'INVALID_PARAM', 'LIBUSB_ERROR', 'cdc_acm', 'ttyACM', 'CVITEK', '3346:1000', '보드가 안 잡혀', '벽돌', 'recovery 버튼', '새 보드'."
user_invocable: true
---

# duo-s-flash — Milk-V Duo S eMMC 굽기

Repo: `~/repos/gh/homeagent-config`. 스크립트 SSOT는 `bsp/flash-emmc.sh` +
`bsp/usb-recovery-prepare.sh`이고, 이 스킬은 그 파일들이 담지 못하는 **판단 기준**을 담는다.

> ⚠️ 이 절차에서 제일 비싼 실수는 잘못 꽂는 게 아니다.
> **usb_dl이 100%와 "USB download complete"를 찍었는데 한 바이트도 안 써진 것**이다.
> §5를 먼저 읽어라. 배너는 증거가 아니다.

---

## 0. 시퀀스 (이것만 지키면 된다)

```bash
cd ~/repos/gh/homeagent-config
sudo ./bsp/usb-recovery-prepare.sh                         # 1. 호스트 준비 (멱등)
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 \
  HOMEAGENT_BSP_ATTEMPTS=10 ./bsp/flash-emmc.sh arm64      # 2. 스크립트 먼저 띄운다
# 3. "REPLUG THE TYPE-C NOW" 뜨면 케이블 꽂기 (§3에서 recovery 버튼 여부 판정)
# 4. 굽기 전에 두 신호 확인 (§4)
# 5. 끝나면 UUID로 증명 (§5)
```

긴 작업이니 tmux로 띄운다. 정상이면 **1~2분이면 끝난다.** 오래 걸리면 그 자체가 이상 신호다.

---

## 1. ISA 계약 — 이걸 틀리면 벽돌과 구분이 안 된다

SG2000은 한 다이에 Cortex-A53(ARM)과 C906(RISC-V)을 얹고 **보드의 물리 슬라이드 스위치**로
어느 쪽이 부팅할지 고른다. eFuse가 아니라 스위치다 — **되돌릴 수 있고, 아무것도 타지 않는다.**
(Milk-V 문서의 "fuse"는 TPU 모델 컴파일 얘기이지 부팅과 무관하다. "퓨징"에 겁먹지 마라.)

| 이미지 | 스위치 | 부팅 후 `uname -m` |
|---|---|---|
| `...-arm64-emmc_*.zip` | **ARM** | `aarch64` |
| `...-riscv64-emmc_*.zip` | **RV** | `riscv64` |

어긋나면 **아예 부팅하지 않는다.** 증상이 벽돌과 똑같아 "구웠는데 죽었다"로 오진하기 쉽다.
롤백은 언제나 가능하다 — 스위치 반대로 돌리고 다른 레인 이미지로 다시 구우면 된다.

## 2. 케이블 — 허브를 쓰면 진다

**Type-C를 호스트에 직결한다.** 허브/독 뒤에서는 `device descriptor read/64, error -110`으로
죽는다. 소프트웨어로 못 고친다. C-to-C든 A-to-C든 상관없다(둘 다 실증).

## 3. recovery 버튼 — 꽂아보고 PID로 판정해라

```bash
lsusb | grep 3346
# 3346:1000 = ROM 다운로드 모드 → 버튼 필요 없다, 바로 구울 수 있다
# 3346:100c = 정상 부팅한 시스템 → 버튼을 누른 채 다시 꽂는다
```

`1000`으로 **저절로** 떨어지는 조건: eMMC가 비었거나(**새 보드가 여기다**), 반대 ISA 이미지가
들어 있거나, 부트 체인이 깨져 있다. 셋 다 아니면 버튼이 필요하다 —
누르고 → 누른 채 꽂고 → 1~2초 뒤 놓는다.

2026-07-24에 양쪽을 다 봤다. 앞선 시도가 부트 체인을 건드려 놨을 땐 버튼 없이 `1000`이었고,
보드가 정상 부팅한 뒤엔 버튼이 필요했다. **"버튼 필요 없더라"는 보드 상태에 대한 관찰이지
절차가 아니다.**

> 중단된 flash가 보드를 망가뜨리진 않는다. 23%에서 끊은 뒤에도 이전 이미지가 그대로 부팅했다.

---

## 4. 핵심 — cdc_acm은 막는 게 아니라 **붙였다 떼는** 것이다

이 절차 전체에서 가장 반직관적인 부분이고, 이틀을 태운 지점이다.

ROM 다운로드 장치는 CDC-ACM 클래스다. 커널의 `cdc_acm`이 인터페이스를 물면 libusb가
claim할 수 없어 빈 `[ERR]`로 죽는다. 그래서 "cdc_acm을 못 붙게 하자"가 자연스러운 결론인데,
**그 방향이 틀렸다.**

### 시도해본 방법과 결과

| 방법 | 결과 |
|---|---|
| `modprobe -r cdc_acm` 단독 | 다음 열거에서 udev가 다시 올린다 |
| `/run/modprobe.d`에 `install cdc_acm /bin/true` | udev가 그냥 로드했다 |
| `drivers_autoprobe=0` | 장치가 **unconfigured**로 남는다 → 인터페이스 0개 → `LIBUSB_ERROR_INVALID_PARAM` |
| udev로 `MODALIAS` 지워 로드 차단 | claim은 성공. 그리고 **모든 벌크 쓰기가 타임아웃** → §5 |
| **붙게 두고, usb_dl 직전에 unbind** | ✅ 정답 |

### 왜 붙어야 하는가

`cdc_acm`의 probe가 CDC 라인 설정(`SET_LINE_CODING` 0x20, `SET_CONTROL_LINE_STATE` 0x22)을
수행하고, 그게 ROM의 데이터 파이프를 연다. 아예 못 붙게 하면 usb_dl이 자기 버전의 같은
제어 전송을 보내는데 **타임아웃난다**:

```
[ERR] config cdc(0x22) failed: LIBUSB_ERROR_TIMEOUT(-7)
[ERR] config cdc(0x20) failed: LIBUSB_ERROR_TIMEOUT(-7)
→ 이후 모든 512KiB 벌크 쓰기가 타임아웃 → 0바이트 → 그런데 "USB download complete"
```

### 그래서 올바른 상태

```
drivers_autoprobe = 1      커널이 열거 안에서 configuration을 붙인다 (경합 구간 없음)
cdc_acm           = 로드됨  열거 때 bind해서 CDC를 초기화한다
unbind            = usb_dl 직전에, 매 시도마다
```

`usb-recovery-prepare.sh`가 앞의 둘을, `flash-emmc.sh`의 `release_cdc_acm()`이 셋째를 한다.

### 굽기 전 확인할 두 신호 — 둘 다 있어야 한다

```bash
lsusb | grep 3346                       # → 3346:1000
sudo dmesg | grep cdc_acm | tail -1     # → cdc_acm 5-1:1.0: ttyACM0: USB ACM device
```

**`ttyACM` 줄이 없으면 굽지 마라.** CDC 설정이 안 된 것이고, 그대로 진행하면 100%를 찍으면서
0바이트를 쓴다.

---

## 5. `USB download complete`는 증거가 아니다

usb_dl은 libusb에 넘긴 청크마다 `updated size` 카운터를 올린다 — **쓰기 성공 여부와 무관하게.**
카운터가 총량에 도달하면 완료 배너를 찍는다. 2026-07-24 실측:

```
[INFO] CVI_USB_PROGRAM
[ERR] usb write failed: LIBUSB_ERROR_TIMEOUT(-7)
[ERR] only send 524288 byte(-7)          ← 매 청크. 한 번도 성공 안 함
...
[INFO] updated size: 809257935/809258127(99%)
[INFO] USB download complete             ← 그런데 eMMC는 전날 파일시스템 그대로
```

`flash-emmc.sh`가 이제 이걸 잡는다(타임아웃 청크 4개 초과면 완료를 무시하고 재시도). 하지만
**최종 증거는 파일시스템 정체성이다:**

```bash
# 스크립트가 끝나면서 이미지 UUID를 출력한다. 보드와 대조해라.
ssh root@192.168.42.1 'dumpe2fs -h /dev/mmcblk0p4 | grep -i UUID'
```

UUID가 다르면 eMMC는 옛 이미지 그대로다. 몇 퍼센트를 봤든 상관없다.

### 속도로도 판별된다

| | 정상 | 거짓 완료 |
|---|---|---|
| 실패 청크 | 0 | 전부 |
| 809 MiB 소요 | **1~2분** | 25분+ |

**오래 걸리면 의심해라.** 매 청크가 타임아웃을 기다리느라 느린 것이다. "예전엔 금방 됐는데"는
정확한 직관이다.

### 그래도 죽이지는 마라

진짜 전송 중일 때 죽이면 되돌릴 수 없다. 2026-07-24에 23%짜리를 "멈춘 것 같다"고 죽였는데,
근거가 전부 틀렸었다:

| 오판 근거 | 실제 |
|---|---|
| 컨테이너 CPU 0.03% | USB I/O 블록 상태. 낮은 CPU가 정상이다 |
| 화면에 아무것도 안 뜬다 | 파이프 블록 버퍼링. 지금은 스트리밍하도록 고쳤다 |
| 90초 넘게 안 끝난다 | 90초는 *장치를 기다리는* 타임아웃이다 |

진행 중인지 보려면 컨테이너 로그를 직접 읽어라 — 아무것도 방해하지 않는다:

```bash
CID=$(docker ps -q --filter ancestor=milkvtech/milkv-duo:latest | head -1)
docker logs --tail 300 "$CID" 2>&1 | tr '\r' '\n' | grep -cE 'only send .* byte\(-7\)'   # 0이어야 한다
docker logs --tail 300 "$CID" 2>&1 | tr '\r' '\n' | grep 'updated size' | tail -1
```

---

## 6. 실패 문자열 감별 — 다섯 가지가 똑같이 생겼다

| 문자열 | 원인 | 조치 |
|---|---|---|
| `device descriptor read/64, error -110` | 허브/독 경유 | Type-C 직결 (§2) |
| `found usb device` 뒤 빈 `[ERR]` | `cdc_acm`이 인터페이스를 물고 있다 | unbind가 안 돈 것 (§4) |
| `LIBUSB_ERROR_INVALID_PARAM` + mutex assertion | unconfigured — 인터페이스 0개 | `autoprobe=1`인지 확인 (§4) |
| `config cdc(0x2x) failed: TIMEOUT` → 모든 청크 `only send ... (-7)` | **`cdc_acm`이 한 번도 bind 안 했다** | 차단 규칙 제거, 모듈 로드 (§4) |
| `config cdc` TIMEOUT이 **퍼센트 없이** 반복 | ROM 상태 기계가 낡았다 (앞선 시도 중단) | **케이블 재삽입** — 재열거로만 초기화된다 |

`set MGN1 flag` / `break` / `Connecting to ROM 2nd stage...`는 **장치를 못 찾은 시도에서도
찍힌다.** 진행 신호가 아니다.

---

## 7. 구운 뒤 합격선

```bash
lsusb | grep 3346:100c                 # 100c = 정상 부팅
ssh root@192.168.42.1                  # 비밀번호 milkv, USB 네트워크 가젯 경유
dumpe2fs -h /dev/mmcblk0p4 | grep -i UUID   # ★ 이미지와 일치해야 진짜다
uname -m                               # aarch64 | riscv64
node -v; ls -d /usr/lib/node_modules/zigbee2mqtt; ls /etc/init.d/ | grep -iE 'zigbee|mosq'
```

**첫 부팅 직후 ssh가 굼뜰 수 있다.** ping은 되는데 세션이 안 붙으면 load를 의심해라
(304MB 보드에 Node 22 + Z2M이다 — 동글 없이 Z2M이 재시도하면 load 3을 찍는다).
포트만 확인하려면:

```bash
exec 3<>/dev/tcp/192.168.42.1/22 && head -c 40 <&3   # 배너가 나오면 dropbear는 살아 있다
```

### Z2M을 쓰던 보드라면 — 굽기 전에 백업

`/var/lib/zigbee2mqtt`에 device DB와 **네트워크 키**가 있고 **reflash하면 날아간다.**
날아가면 모든 기기를 다시 페어링해야 한다.

```bash
ssh root@192.168.42.1 'tar cz -C /var/lib zigbee2mqtt' > z2m-backup-$(date +%Y%m%dT%H%M%S).tar.gz
```

---

## 8. 새 보드를 굽는 경우

새 보드가 오히려 쉽다. eMMC가 비어 있어 ROM이 그냥 통과시키므로 **recovery 버튼이 필요 없다** —
꽂으면 바로 `3346:1000`이다. §0 시퀀스를 그대로 쓰되 §1 스위치만 반드시 확인해라.

---

## 9. 정리 — 굽고 나면

`usb-recovery-prepare.sh`가 남기는 건 udev 안전망 규칙 하나뿐이고, `idProduct=="1000"`에만
매치하므로 다른 장치에 영향이 없다. NixOS에서는 `/etc/udev/rules.d`가 읽기 전용이라
`/run/udev/rules.d`에 떨어지고, 재부팅하면 사라진다(그래서 매번 prepare를 다시 돌린다).

```bash
sudo ./bsp/usb-recovery-prepare.sh --revert
```

---

## 10. 이 절차를 고칠 때

- 스크립트 SSOT는 `bsp/flash-emmc.sh` 상단 PROCEDURE 블록 + `bsp/usb-recovery-prepare.sh` 헤더.
- **세션에서 관측한 것은 반드시 스크립트나 이 스킬로 내려라.** 2026-07-23에
  "autoprobe=0이면 구성이 안 붙는다"를 관측하고도 flash 실패와 연결하지 않아 문서에 안 들어갔고,
  다음 날 같은 자리에서 하루를 태웠다.
- **셸 함정 하나**: `set -o pipefail` 아래에서 `lsmod | grep -q '^cdc_acm'`는 모듈이 로드돼
  있어도 실패로 판정된다. `grep -q`가 첫 매치에서 종료 → `lsmod`가 SIGPIPE(141) → pipefail이
  파이프라인을 실패로 본다. 이 한 줄 때문에 cdc_acm 처리 블록이 통째로 조용히 건너뛰어졌다.
  `/proc/modules`를 직접 읽어라.
- 이미지 빌드는 별개다 — `bsp/README.md`("Building on a remote host")가 SSOT.
