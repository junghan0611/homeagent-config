# ZBDongle-E 코디네이터 펌웨어

x86/개발 PC에서 z2m(Zigbee2MQTT)를 돌리기 위한 **Sonoff ZBDongle-E(EFR32MG21)**
코디네이터 펌웨어 모음. 보드(SMHub Nano, EFR32**MG24**)와 스택 버전을 맞춰,
동글 lane과 보드 lane이 **같은 EmberZNet/EZSP**로 재현되게 한다.

## 파일

| 파일 | 프로토콜 / 역할 | 버전 | 흐름제어(빌드) | Baud | sha256 |
|---|---|---|---|---|---|
| `zbdonglee_zigbee_ncp_7.4.2.0_hw_flow_115200.gbl` | Zigbee NCP (EZSP) | EmberZNet **7.4.2.0** / EZSP **13** | hw¹ | 115200 | `42fcf8a2…4557a6` |
| `zbdonglee_zigbee_ncp_8.0.3.0_sw_flow_115200.gbl` | Zigbee NCP (EZSP) | EmberZNet 8.0.3.0 | sw | 115200 | `b9a630cd…872b17` |
| `zbdonglee_openthread_rcp_2.5.3.0_no_flow_460800.gbl` | OpenThread RCP | 2.5.3.0 | none | 460800 | `c949a49b…50cf4e` |

¹ 빌드명은 `ncp-uart-**hw**`지만, ZBDongle-E는 RTS/CTS가 물리 배선돼 있지 않아
실제 링크는 software flow control로 돈다 (아래 z2m 설정 참조).

- 출처: [darkxst/silabs-firmware-builder](https://github.com/darkxst/silabs-firmware-builder)
  `firmware_builds/zbdonglee/` (공개 빌드).
- 파일명은 상류 빌드명을 `zbdonglee_<proto>_<role>_<version>_<flow>_<baud>.gbl`
  규칙으로 정규화한 것.

## 왜 7.4.2.0인가 — 보드 버전 정렬

- 보드(SMHub Nano) MG24 코디네이터 = EmberZNet **7.4.2 [GA] / EZSP 13** (실측, `docs/SMHUB.md`).
- 동글도 **7.4.2.0**으로 통일하면 z2m herdsman/EZSP 계층이 보드·동글에서 동일하게 재현된다 →
  x86 개발 lane에서 검증한 동작이 보드로 그대로 이어짐.
- 최신 스택 실험이 필요할 땐 같은 디렉토리의 `8.0.3.0`을 쓴다(버전 정렬 목적 아님).

## 플래시 절차 (실측 2026-07-06)

ZBDongle-E(`-E` = EFR32)는 DTR/RTS 자동 부트로더 배선이 없어 **물리 버튼**이 유일한
진입로다(`-P`(TI) 모델만 자동). RST 탭 방식은 안 먹었고, **BOOT 누른 채 USB 꽂기**가 확실했다.

```bash
# 1) 부트로더 진입: USB 뽑고 → BOOT 누른 채로 USB 꽂고 → 2초 뒤 BOOT 떼기
#    확인: Gecko Bootloader v1.12.00 메뉴가 115200에서 뜬다.

# 2) 플래시 (universal-silabs-flasher, uvx로 설치 없이 실행)
uvx --from universal-silabs-flasher universal-silabs-flasher \
    --device /dev/ttyUSB0 flash \
    --firmware zbdonglee_zigbee_ncp_7.4.2.0_hw_flow_115200.gbl

# 3) 검증
uvx --from universal-silabs-flasher universal-silabs-flasher \
    --device /dev/ttyUSB0 probe
# → Detected ApplicationType.EZSP, version '7.4.2.0 build 0' at 115200 baud
```

## z2m 설정값

```yaml
serial:
  port: /dev/ttyUSB0
  adapter: ember
  baudrate: 115200
  rtscts: false
```

> **실측(2026-07-06)**: ZBDongle-E는 RTS/CTS 배선이 없어 `rtscts: true`면 z2m ember의
> ASH 핸드셰이크가 5초 주기 리셋 루프에 빠진다. `false`로 두면 z2m가 "RTS/CTS off →
> software flow control"로 자동 전환해 정상 연결(`Coordinator firmware version 7.4.2 [GA]`,
> EZSP 13). 빌드명이 `ncp-uart-hw`여도 실제 링크는 flow control 없이 돈다.
> 보드(내부 UART `/dev/ttyS1`)도 `rtscts: false` — 시리얼 설정까지 정렬된다.
