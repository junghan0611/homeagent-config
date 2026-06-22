# THP23-ZB-X Liberation — Research Notes

SMHUB Nano 도착 전, 손에 있는 Tuya 제품 **THP23-ZB-X**(모듈 THP23-X-M 기반)를 오픈소스 포크로 해방·소유하기 위한 조사 정리. NEXT.md ACTIVE #1의 상세 SSOT.

> 상태: 데스크 리서치 1차 완료(2026-06-22). 실보드 물리 검사는 1차 완료, UART 진입은 미진행.

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

## 4. Base / Reference 후보 비교

활성도 점검(§9) 반영. mainline이 base, 죽은 포크는 reference.

| 후보 | 성격 | 상태 | 역할 |
|---|---|---|---|
| **mainline Linux + U-Boot + Buildroot 2025.x** | upstream base | 활발(in-tree SSD202D DTS) | **long-term base** |
| buildroot_idosom2d01 / linux-chenxing kernel·docs | porting reference | 코드 정체(2023), 문서 일부 활발 | DTS/UBI/UART/TFTP recipe + missing-driver diff |
| **vendor SSD202 SDK** (8ms/Sigmastar) | vendor oracle | 실용 bring-up, redistribution 불명확 | first-boot oracle / partition·driver 참고 (base 아님) |
| wireless-tag/openwrt-ssd20x | old userland fork | 2022 / "hacky" / SSD202D 미명시 | historical only |

## 5. 결정: Buildroot 우선 + SMHUB 정합

- **Buildroot를 1차로 간다.** SSD202D 오픈소스 경로(linux-chenxing, vendor SDK) 양쪽이 Buildroot 중심이고, SMHUB 쪽 **SG2000/Milk-V `duo-buildroot-sdk`(V2, RISC-V+ARM)도 Buildroot 기반**이라 빌드 워크플로가 일관된다.
- 단 정합은 **빌드시스템·운영 워크플로 수준**이다. arch는 다르다: **SSD202D = ARMv7 Cortex-A7**, **SG2000 = RISC-V C906 + ARM Cortex-A53(aarch64)**. 동일 이미지/툴체인이 아니라 "같은 Buildroot 방식으로 두 보드를 운영"하는 정합.
- 역할 구분 (활성도 점검 반영, §9):
  - **Identity / long-term base** = **mainline Linux + mainline U-Boot + Buildroot 2025.x** (SSD202D DTS in-tree, 활발). 커뮤니티 코드 포크(buildroot_idosom2d01/chenxing kernel)는 2022~23 정체 → mainline 위 **포팅 레시피·드라이버 diff로만** 사용.
  - **Bring-up oracle / fallback** = vendor SSD202 SDK(8ms/Sigmastar, Buildroot 기반). 빠르게 부팅·DTS·드라이버·partition을 떠서 참고.
  - **강등** = OpenWrt-ssd20x(hacky, 2022). 후순위.
- 단, **첫 실보드 flash 이미지가 반드시 linux-chenxing일 필요는 없다.** stock bootlog/partition/env 확보 → 양쪽 desk build feasibility 비교 후 첫 write를 결정(§6).

## 6. 권장 bring-up 순서

1. **물리 검사**(GLG): PCB 칩 마킹(SSD202D/EFR32 part·EFR32와 SoC 연결 UART), SPI NAND 칩, UART 패드 위치, 점퍼.
2. **UART 콘솔 진입**: USB-UART 3.3V 연결, 보레이트 탐색(115200 우선), boot log 확보. 첫 세션에서 `help`·`printenv`·`mtdparts`·`nand info`·`nand bad` 캡처(가용 명령·레이아웃·env 확인).
3. **공식 U-Boot 진입**(§3) → 위 캡처로 stock partition/env 실측.
4. **stock 백업 + 검증**: NAND 전체 덤프 + nvram 인증 파라미터. 덤프 파일 **크기/해시/오프셋과 복원 명령까지 기록.** ← 이 검증 끝나기 전 `nand erase`/`nand write` 금지.
5. **desk build**: **mainline Linux/U-Boot + Buildroot 2025.x** 보드파일 포팅을 1차 desk build로. buildroot_idosom2d01 레시피 + linux-chenxing/vendor diff를 참고. 빠른 first-boot oracle이 필요하면 vendor SSD202 SDK도 병행 build. **첫 write 대상은 이 비교 후 결정.**
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
- **mainline=베이스지만 THP23 DT는 포팅 대상** — 첫 write 전 반드시 확인: ① mainline U-Boot에서 THP23 SPI NAND geometry/UBI 레이아웃 일치, ② PM_UART가 실제 THP23 헤더와 일치(§8·§11), ③ mainline DTS(`som2d01`/`gw302`)의 ethernet/reset/GPIO/EFR32 UART가 THP23 보드와 얼마나 다른지.

## 8. 실보드 확인 + 시리얼 연결 (2026-06-22, 검증됨)

실보드 분해 + 클론 리포 대조로 확정. 보드 실크 **`THP23-X_V1.3.0`** (Model `THP23-X`, P/N `2.05.08.01628`).

확인된 부품: 중앙 **SSD202D**(코어) / 하단 **EFR32MG21**(Zigbee, 실드 안) / 우상단 **TY001 Wi-Fi**(IPEX) / 코어 옆 **SPI NAND** / 좌상 **RJ45**+마그네틱 / 좌 **USB-C**(전원) + 우 **USB-A** / CR1632 RTC / **좌하단 4핀 through-hole 헤더(UART 후보)**.

### 시리얼 연결 (동일 SSD202D SoM = IDO-SOM2D01 기준, linux-chenxing 검증)

부트 ROM·u-boot·커널이 공통으로 쓰는 콘솔은 **PM_UART**:

| 보드 | USB-Serial 어댑터 |
|---|---|
| `PM_UART_RX` (모듈 pin 25) | ← 어댑터 **TX** |
| `PM_UART_TX` (모듈 pin 26) | → 어댑터 **RX** |
| `GND` | ↔ GND |

- **콘솔: `ttyS0`, 115200 8N1.** (buildroot_idosom2d01 README·infinity2 로그 다중 확인)
- **3.3V 로직** — 5V 금지. **보드 전원은 자체 USB-C로 공급하고, 어댑터 VCC는 연결하지 않는다(GND/TX/RX만).**
- 좌하단 4핀 헤더의 핀 순서는 **멀티미터로 확정할 것**: **GND**(보드 GND/USB 쉴드와 도통), **TX**(평상 3.3V 하이·부팅 시 버스트), **RX**, (VCC). RX/TX 헷갈리면 한 번 바꿔 연결.
- 주의: PM_UART 핀에는 ISP용 i2c slave도 물려 있음(SPI NOR/NAND 갱신용). 콘솔과 공유.

### 플래시 레이아웃 (SPI NAND, ISP 기준)

- `GCIS/CIS` @ `0x0` · `IPL` @ `0x140000` · `u-boot SPL` @ `0x200000` · 나머지 = **UBI**.
- UBI 볼륨: `uboot`(1MiB,static) / `env`(256KiB) / `kernel`(16MiB) / `rescue`(16MiB) / `rootfs`(나머지).

### THP23는 blank 모듈이 아님 (중요)

stock 출하품이라 IPL+u-boot가 이미 정상. blank 모듈용 vendor ISP 플래시는 **brick 시 fallback**. 정상 경로:
1. **stock u-boot interrupt** — Tuya 공식 `nvram set persist.uboot.enter on && nvram commit` → 재부팅 중 Enter (§3).
2. backup(§3·§7 게이트) 후, u-boot SPL의 **serial(ymodem `loady`) 또는 ethernet TFTP**로 rescue kernel 부팅 → UBI 재구성.
3. **SSD202D는 DT를 명시해야 함**: `bootm ${loadaddr}#ssd202d-som2d01` 안 하면 커널 부팅 중 락업.

## 9. 참고 리포 세트 (`~/repos/3rd/tuya/`, 활성도 점검 2026-06-22)

**결론: 커뮤니티 *코드* 포크는 대부분 동면(2022~23). 단단한 베이스는 mainline 자체.** 마지막 커밋 기준 등급:

### 살아있는 단단한 베이스 (upstream, 활발) — 로컬 클론 아님, 빌드 시 사용
- **Linux mainline** (torvalds/kernel.org) — SSD202D `infinity2m` DTS + 드라이버 **in-tree**(`arch/arm/boot/dts/sigmastar/`, ido-som2d01 포함). 6.16(2025) 등 활발. ← 커널 베이스.
- **U-Boot mainline** — sstar/SSD20x SPL upstream(2021~). ← 부트로더 베이스.
- **Buildroot mainline** (2025.x, 활발) — ssd202d defconfig 없음 → som2d01 보드파일을 포팅해 사용.

### 참고용 클론 (유용하나 정체/정적 — 포팅 레시피·드라이버 diff)
| 디렉토리 (origin) | 최신 커밋 | 역할 |
|---|---|---|
| `linux-chenxing.org` | 2026-05 ✅ | infinity2 문서·핀아웃·ISP·boot ROM (문서만 활발). `infinity2/ido-som2d01/`·`ip/commonpins.md` |
| `SigmaStar-SSD202D-Docs` (iscle) | 정적 archive | **주변장치 datasheet PDF**: EMAC(ethernet)/GPIO/I2C/UART/RTC/PWM — 드라이버·DT 작업에 핵심 |
| `buildroot_idosom2d01` (fifteenhex) | 2023-06 | SoM Buildroot 레시피(UART/ymodem/UBI/TFTP 절차). **mainline 위로 포팅** |
| `linux-chenxing-kernel` (mstar_v6_7_rebase) | 2023-12 | mainline에 아직 없는 WIP 드라이버 diff 참고. rebase가 v6.7에서 멈춤 |

### oracle (base 아님)
- **vendor SSD202 SDK** (8ms/Sigmastar): first-boot oracle / partition·driver 참고. git URL·라이선스 확정 후 `tuya/`에 **read-only 클론 예정**. ⚠️ **공개 repo(homeagent-config)에 SDK 파일/패치 반입 금지.**

### 강등 (죽음/저품질)
- `buildbot` (2022-02, 죽은 CI), `openwrt-ssd20x` (2022-02, 커뮤니티 평 "hacky"). 역사적 참고만.
- Miyoo Mini buildroot: 활발하나 게임기 특화 + "not ready" → 게이트웨이 베이스로 부적합.

THP23 최근접 DT(mainline/chenxing 공통): `mstar-infinity2m-ssd202d-wirelesstag-ido-som2d01.dtsi`(동일 모듈) + 게이트웨이형 `...-gw302.dts`. bootm 노드명 `ssd202d-som2d01`.

## 10. LAN 정찰 결과 (2026-06-22, 무땜)

stock 보드를 이더넷에 연결하고 스캔:

- 식별: 호스트네임 **`SmartGateway-BDE2`** (MAC `00:33:7A:3B:BD:E2`, 끝자리 BDE2 일치), DHCP IP **192.168.0.134**, ping ttl=64(Linux).
- `nmap -sT -p-` 전체 포트: **`6668/tcp` 단 하나만 open** = **Tuya 로컬 제어 프로토콜**(암호화 디바이스 제어). SSH(22)·telnet(23)·web(80)·2333 전부 닫힘.
- **결론: LAN-only 해방 불가.** 6668은 셸/root를 주지 않는다. 펌웨어 교체용 네트워크 진입로 없음 → **시리얼 콘솔 필수.**
- 부수효과: 6668 open = stock 정상 부팅 중. 그리고 u-boot 진입 후 **이미지 전송은 이 LAN(TFTP)으로** 하면 빠르다.

## 11. UART 4핀 헤더 확정법 (땜 없이)

좌하단 4핀 through-hole이 정말 UART인지 가리는 절차:

1. **GND 찾기** (멀티미터 도통, 전원 OFF): 확실한 GND(USB-C 쉴드/RJ45 쉘/전해캡 −/코인셀 −)와 4핀 각각 도통 → 삑- 울리는 핀 = GND(보통 끝핀).
2. **VCC/TX/RX 구분** (DC 전압, 전원 ON, 검은 프로브=GND핀):
   - **VCC** = 3.3V 고정(안 흔들림)
   - **TX 후보** = 평상 3.3V인데 **부팅 순간 비동기 버스트**(데이터 전송). 단 I2C 등도 부팅 중 activity가 있을 수 있으니 전압/버스트는 *후보 식별*까지 — **최종 판정은 3단계 boot log.**
   - **RX** = 3.3V 풀업, 잔잔
3. **결정타** (USB-Serial 3.3V, 무땜): GND 연결 + 어댑터 **RX**만 TX 후보 핀에 점퍼핀 임시접촉 → `screen /dev/ttyUSB0 115200` + 전원 인가 → **boot log(SigmaStar/U-Boot 배너) 뜨는 핀 = TX = UART 확정.**
   - 어댑터 TX(출력)는 핀 확정 전 연결 금지(읽기 먼저). 핀 피치 2.54mm면 dupont 그대로 사용.

## 12. 작업 분담 — 아웃소싱 vs GLG self

GLG는 납땜을 직접 못 함 → 물리/납땜은 외주, 나머지는 무땜으로 GLG가 직접.

| 구분 | 항목 | 비고 |
|---|---|---|
| **아웃소싱(맡김)** | 좌하단 4핀 UART 확정(§11) + **핀헤더 4핀 납땜** | 산출물: boot log + 안 끊기는 시리얼 헤더. §11 절차를 작업지시서로 전달 |
| **GLG self (무땜)** | 3.3V USB-Serial 어댑터 확보 | CP2102/CH340/FT232 3.3V |
| **GLG self** | TFTP 서버 셋업(192.168.0.x) | 이미지 전송용 |
| **GLG self** | `buildroot_idosom2d01` desk build | u-boot/kernel/rescue/rootfs FIT 산출 |
| **GLG self** | (헤더 오면) stock u-boot 진입 + `help/printenv/mtdparts/nand info/nand bad` 캡처 → stock NAND+nvram 백업(§7 게이트) | 시리얼+LAN |
| **GLG self** | rescue 부팅(`bootm ...#ssd202d-som2d01`) → UBI 재구성 → open image flash | §8 경로 |

> GLG self 선행작업은 "읽기/빌드/전송 인프라 준비"까지. **실보드 write/erase는 stock 백업 게이트(§7) 전 금지.**

### 아웃소싱 작업지시 — 산출물 (받을 것)

- 4핀 헤더 핀맵 사진: 보드 방향 기준 `GND / TX(board→adapter RX) / RX(adapter TX→board) / VCC?` 라벨링
- 각 핀 측정값: 전원 OFF 도통, 전원 ON DC 전압, 부팅 시 TX 후보 변화 여부
- **boot log 텍스트(또는 캡처)**: Boot ROM/IPL/U-Boot 배너 보이는 115200 8N1 로그
- 납땜 후 사진: 헤더 방향/핀1 표시/쇼트 없음
- 핀 피치 실측(2.54mm 여부, 아니면 규격 기록)

### 아웃소싱 금지사항

- USB-Serial **VCC를 보드에 연결 금지** — 보드 전원은 자체 USB-C
- 확정 전 **어댑터 TX를 보드에 연결 금지** — 먼저 GND + adapter RX만으로 board TX 읽기
- **5V TTL 어댑터 금지, 3.3V logic만**
- **ISP/flash/write 금지** — 외주 범위는 *UART 확인 + 헤더 납땜 + boot log 산출까지만*

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
