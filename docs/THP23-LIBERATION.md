# THP23-ZB-X Liberation — Research Notes

SMHUB Nano 도착 전, 손에 있는 Tuya 제품 **THP23-ZB-X**(모듈 THP23-X-M 기반)를 오픈소스 포크로 해방·소유하기 위한 조사 정리. NEXT.md ACTIVE #1의 상세 SSOT.

> 상태: 데스크 리서치 1차 완료(2026-06-22). 실보드 물리 검사·UART 진입은 미진행.

## 1. 하드웨어 사실

| 항목 | 값 |
|---|---|
| SoC | Sigmastar **SSD202D** (ex-MStar). Dual Cortex-A7 @ 1.2GHz, 2D GPU |
| RAM | **128MB DDR3, on-chip (SiP)** — 칩 패키지 내장 |
| 플래시 | **SPI NAND** (THP23 stock 레이아웃은 256MB NAND 기준) |
| 무선 | onboard **EFR32/Gecko-class** Zigbee 라디오(제품 ZB 변종) + Wi-Fi **TY001** 모듈 |
| 유선 | onboard 10/100M Ethernet |
| 콘솔 | 디버그 UART `PM_UART_RX/TX` (모듈 datasheet pin 25/26) |
| 비교 SoM | mainline DT가 존재하는 **Wireless Tag IDO-SOM2D01 / IDO-SBC2D06**가 같은 SSD202D + 256MB SPI NAND 구성 — 드라이버 참고점 |

## 2. 부팅 / 플래시 구조 (중요)

- Boot ROM은 **SPI NOR 또는 SPI NAND에서만** 부팅. **SD/eMMC 부팅 불가** (Boot ROM 16KB immutable, SD 드라이버 없음).
  → **SD카드로 이미지 갈아끼우는 전략은 불가.** 플래시는 U-Boot에서 SPI NAND에 직접 쓴다.
- 부팅 체인: `IPL`(~48KB SRAM) → `IPL_CUST` / mainline에선 `U-Boot SPL`(DRAM) → `U-Boot` → DT + kernel.
- 복구: U-Boot SPL을 **UART로 재주입** 가능 → 부트로더 깨져도 serial 복구 경로 있음. (TFTP 서버 필요)

## 3. Tuya 공식 해방 경로 (저위험 — glitch/exploit 불필요)

Tuya 자체 문서(THP23-X-D firmware flashing)에 U-Boot 진입·플래시 절차가 공개돼 있다. 즉 **공식 serial + U-Boot 만으로 stock 백업·재플래시 가능**.

1. **U-Boot 진입 활성화** (running system에서):
   ```
   nvram set persist.uboot.enter on && nvram commit
   ```
   재부팅 중 `Enter` 길게 눌러 U-Boot 진입.
2. **자격증명**: 로그인 `root` / `tygw@SSD20x`, U-Boot 비번 `tygw@SSD20x`.
3. **stock 플래시 레이아웃**(256MB all-in-one 기준):
   - `ssd20x_256m_all.img.0` → `0x0`
   - `ssd20x_256m_all.img.1` → `0x2d00000`
4. **TFTP 플래시 예시**:
   ```
   setenv serverip 192.168.1.128
   setenv ipaddr 192.168.1.2
   nand erase.chip
   tftp 0x21000000 ssd20x_256m_all.img.0
   nand write 0x21000000 0x0 ${filesize}
   tftp 0x21000000 ssd20x_256m_all.img.1
   nand write 0x21000000 0x2d00000 ${filesize}
   ```

### ⚠️ erase 전 반드시 백업
`nand erase.chip`은 전체 소거. 다음을 먼저 보존:
- **stock NAND 전체 덤프**(원복용).
- **nvram 인증 파라미터** (`nvram show`): `UUID`, `AUTHKEY`, `slave_mac1`, `master_mac`, `bsn`.
  복원: `nvram set UUID ...` / `nvram set AUTHKEY ...` / `nvram commit`.
  → 이걸 잃으면 stock 복귀·Tuya 재인증/재페어링이 깨질 수 있음.

## 4. 오픈소스 포크 후보 비교

| 후보 | 빌드시스템 | SSD202D | 성숙도 | 비고 |
|---|---|---|---|---|
| **linux-chenxing** (mainline + buildbot) | **Buildroot** | ○ (IDO-SOM2D01 mainline DT 존재, i2c/spi/일부 DMA upstream) | 중 — mainline 추적, "own the box"에 최적. ethernet/display/주변장치 실보드 검증 필요 | `buildbot/kernel_ssd20xd.its` FIT 빌드. **1차 후보** |
| **Vendor SSD202 SDK** (Sigmastar/8ms.xyz) | Buildroot 기반 | ○ | 상 — 가장 빨리 부팅, 가장 덜 열림(vendor kernel) | DT/드라이버 참고·**fallback**용 |
| **wireless-tag/openwrt-ssd20x** | OpenWrt | △ (SSD201/202, **SSD202D 명시 없음**) | 하 — OpenWrt 18.06 / GCC8.2, ~44 commits, 갱신 정체 | 게이트웨이형 userland 빠른 대안이나 구식. 후순위 |

## 5. 결정: Buildroot 우선 + SMHUB 정합

- **Buildroot를 1차로 간다.** SSD202D 오픈소스 경로(linux-chenxing, vendor SDK) 양쪽이 Buildroot 중심이고, SMHUB 쪽 **SG2000/Milk-V `duo-buildroot-sdk`(V2, RISC-V+ARM)도 Buildroot 기반**이라 빌드 워크플로가 일관된다.
- 단 정합은 **빌드시스템·운영 워크플로 수준**이다. arch는 다르다: **SSD202D = ARMv7 Cortex-A7**, **SG2000 = RISC-V C906 + ARM Cortex-A53(aarch64)**. 동일 이미지/툴체인이 아니라 "같은 Buildroot 방식으로 두 보드를 운영"하는 정합.
- 역할 구분:
  - **Identity / long-term target** = linux-chenxing + Buildroot. "own the box"에 부합, 최종 지향.
  - **Bring-up oracle / fallback** = vendor SSD202 SDK. 빠르게 부팅·DTS·드라이버·partition을 떠서 참고.
  - **Userland fallback** = OpenWrt-ssd20x. 후순위.
- 단, **첫 실보드 flash 이미지가 반드시 linux-chenxing일 필요는 없다.** stock bootlog/partition/env 확보 → 양쪽 desk build feasibility 비교 후 첫 write를 결정(§6).

## 6. 권장 bring-up 순서

1. **물리 검사**(GLG): PCB 칩 마킹(SSD202D/EFR32 part·EFR32와 SoC 연결 UART), SPI NAND 칩, UART 패드 위치, 점퍼.
2. **UART 콘솔 진입**: USB-UART 3.3V 연결, 보레이트 탐색(115200 우선), boot log 확보. 첫 세션에서 `help`·`printenv`·`mtdparts`·`nand info`·`nand bad` 캡처(가용 명령·레이아웃·env 확인).
3. **공식 U-Boot 진입**(§3) → 위 캡처로 stock partition/env 실측.
4. **stock 백업 + 검증**: NAND 전체 덤프 + nvram 인증 파라미터. 덤프 파일 **크기/해시/오프셋과 복원 명령까지 기록.** ← 이 검증 끝나기 전 `nand erase`/`nand write` 금지.
5. **desk build 비교**: linux-chenxing(Buildroot)·vendor SSD202 SDK 양쪽을 빌드해 DTS·mtd·UART·ethernet feasibility 비교. **첫 write 대상은 이 비교 후 결정** — 반드시 linux-chenxing이 먼저일 필요는 없다(vendor SDK로 먼저 부팅을 떠 oracle로 쓸 수 있음).
6. **TFTP 환경** 구성(serverip/ipaddr) → 결정된 오픈소스 image 시험 플래시.
7. **EFR32 경로**: SoC↔EFR32 연결 UART/리셋·부트로더 핀 식별 → Zigbee NCP(zigbee2mqtt/ezsp) 1 디바이스 페어링 증명.
8. **128MB 증거**: 부팅 후 RSS/process 측정(MQTT+Z2M 등 hub 서비스 하한 확인).

## 7. 리스크 / 주의

- **SiP 128MB 고정** — 확장 불가. Node/matter.js + Z2M 동시는 빡빡. hub 서비스 하한 측정 대상.
- **SD 부팅 불가** — 복구는 U-Boot(NAND) + UART SPL 재주입에 의존. TFTP 서버 필수.
- **nvram 인증키 분실 위험** — erase 전 백업 안 하면 stock/Tuya 복귀 불가능 가능성.
- **Erase 게이트** — `nand erase.chip`/`nand write`는 ① stock NAND 덤프 + 크기/해시/오프셋·복원 명령 기록, ② nvram 덤프, ③ 복구 경로(U-Boot SPL UART 재주입+TFTP) 확인이 끝나기 전엔 금지. "백업했다"가 아니라 *복원까지 검증* 기준.
- **U-Boot 백업 명령 가용성** — Tuya 문서의 TFTP `nand write`는 공개돼 있으나, 업로드/덤프(`tftpput`/`nand read`/`md`)는 stock U-Boot 빌드에 따라 없을 수 있다. 첫 UART 세션의 `help` 캡처로 가용 명령을 먼저 확인. 없으면 SPL/mainline U-Boot 재주입 후 덤프 경로를 따로 마련.
- **OpenWrt 포크 구식** — SSD202D 미명시 + 18.06. 검증 비용 큼, 후순위.
- **EFR32 라디오 펌웨어** — Tuya stock의 EFR32 펌웨어/연결 방식 미확인. **stock radio가 EZSP/NCP로 바로 쓰인다는 전제는 두지 않는다.** 필요 시 MG24/Gecko NCP 펌웨어(EmberZNet/EZSP) 재플래시는 별도 단계로 본다.

## Sources

- [linux-chenxing.org — infinity2 / SSD202](http://linux-chenxing.org/infinity2/)
- [linux-chenxing SSD202D boot process (Discussion #45)](https://github.com/linux-chenxing/linux-chenxing.org/discussions/45)
- [linux-chenxing/buildbot kernel_ssd20xd.its](https://github.com/linux-chenxing/buildbot/blob/master/kernel_ssd20xd.its)
- [Tuya THP23 gateway firmware flashing guide](https://developer.tuya.com/en/docs/iot-device-dev/tuyaos-gateway-product-thp23-firmware?id=Kdnr529pvvi1f)
- [Tuya THP23-X-D development board](https://developer.tuya.com/en/docs/iot-device-dev/tuyaos-gateway-multi-mode-gateway?id=Kc5xgv7cxg27a)
- [wireless-tag-com/openwrt-ssd20x](https://github.com/wireless-tag-com/openwrt-ssd20x)
- [Wireless Tag IDO-SBC2D06 mainline DT patch (kernel.org)](https://patchwork.kernel.org/project/linux-arm-kernel/patch/20210923170747.5786-4-romain.perier@gmail.com/)
- [8MS SSD202 SDK quick start](https://docs.8ms.xyz/en/develop/sdk/getStart/ssd202.html)
- [Milk-V Duo Buildroot SDK (SG2000)](https://milkv.io/docs/duo/getting-started/buildroot-sdk)
- [CNX: SigmaStar SSD201/SSD202 mainline Linux gateway](https://www.cnx-software.com/2021/01/29/sigmastar-ssd201-ssd202-powered-4g-lte-industrial-gateway-made-to-run-mainline-linux/)
</content>
</invoke>
