# TARGET DEVICE — absorbed

이 문서의 현재 유효한 보드 전략은 [`../VERSION.md`](../VERSION.md)의 **Target device strategy — Hailo/RK boards** 섹션으로 압축 흡수했다.

## 현재 결정

- HomeAgent 개발/검증 기준은 RPi5 + Yocto Scarthgap.
- AI 가속은 Hailo-8 계열 우선. OPi5 내장 RKNN/vendor 6.1 경로는 parked.
- 새 보드는 Yocto BSP가 검증된 플랫폼만 후보로 본다.
- Android 월패드는 HomeAgent를 Android 전용으로 바꾸는 방향이 아니라 연동/bridge 대상으로 본다.

## 보류 후보군

| 후보 | 이유 | 상태 |
|------|------|------|
| RK3588 + Hailo-8 M.2 | 양산 후보, Android/Yocto 생태계 | 보류 |
| Geniatech APC3588-AI | RK3588 + Hailo 옵션 산업용 후보 | 보류 |
| Banana Pi BPI-M7 / OPi5 Plus / NanoPi T6 | RK3588 + M.2 후보군 | 보류 |
| NXP iMX8M Plus | 산업용/Hailo Yocto 성숙 | 보류 |

새 보드 선정이 필요하면 `VERSION.md`, `HARDWARE.md`, OPi5 llmlog `20260331T114944`를 먼저 확인한다.
