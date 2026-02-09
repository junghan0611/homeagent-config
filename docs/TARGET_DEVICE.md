# TARGET DEVICE - Hailo AI 가속기 지원 타겟 디바이스

> RPi5 + Hailo 개발 플랫폼의 양산/확장 타겟 조사 결과.
> **Yocto-first 전략**: Yocto BSP가 확보된 플랫폼만 타겟으로 선정한다.

## 개발 전략

```
[Phase 1] RPi5 + Hailo-8L        → Yocto Scarthgap 개발/검증 (현재)
[Phase 2] RK3588 + Hailo-8       → Yocto 포팅 (양산 타겟)
[Phase 3] RK3588 + Android 연동  → 월패드 업체 대응
```

### 왜 Yocto-first인가?

```
1. 하드웨어 삽질 최소화
   - Yocto BSP가 검증된 보드 = 드라이버/DT/커널 안정
   - "보드 받았는데 부팅 안 돼요" 리스크 제거

2. Android는 따라온다
   - RK3588 Yocto BSP 있음 → Android SDK도 공식 지원
   - Yocto에서 검증된 디바이스트리/드라이버 = Android HAL 포팅 용이

3. 재현 가능한 빌드
   - 오프라인 빌드, 라이선스 추적, 보안 감사 모두 Yocto 기반
   - Android 전용 개발은 하지 않음 (연동만 제공)
```

## Hailo 제품 라인업

| 모델 | 성능 | 폼팩터 | 용도 |
|------|------|--------|------|
| **Hailo-8L** | 13 TOPS | M.2 Key A+E / B+M | 엔트리급, RPi5 HAT |
| **Hailo-8** | 26 TOPS | M.2 Key M (PCIe Gen3) | 양산급 Edge AI |
| Hailo-10 | TBD | TBD | 차세대 (미출시) |

- 현재 프로젝트: RPi5 + Hailo-8L로 개발
- 양산 타겟: Hailo-8 (M.2 PCIe) → RK3588 보드에 장착

## 타겟 보드 비교

### 1순위: RK3588 기반 (양산 추천)

| 보드                     | M.2 슬롯                | 가격     | Yocto                      | Android       | 비고                                        |
|--------------------------|-------------------------|----------|----------------------------|---------------|---------------------------------------------|
| **Banana Pi BPI-M7**     | Key M (PCIe 3.0)        | $100-150 | ✅ meta-rockchip scarthgap | ✅ Android 12 | **Hailo 공식 연동 문서 있음**, 2x 2.5GbE    |
| **Geniatech APC3588-AI** | Key M (Hailo 내장 옵션) | $125-150 | ✅                         | ✅            | **산업용 완제품**, RK3588+Hailo-8 결합 제품 |
| Orange Pi 5 Plus         | Key M                   | $90-130  | ✅                         | ✅            | 커뮤니티 검증, 가성비                       |
| NanoPi T6                | Key M                   | ~$100    | ✅                         | ✅            | FriendlyElec, 소형                          |

**RK3588 핵심 포인트**:
- 내장 NPU 6 TOPS + Hailo-8 M.2 = **총 32 TOPS**
- Rockchip 공식 Android 12/13 SDK 지원
- meta-rockchip Yocto BSP: Kirkstone + **Scarthgap 지원**
- 한국 월패드 업체들이 RK3568/RK3588 Android 기반 제품을 이미 사용 중

### 2순위: NXP iMX8M Plus (산업용)

| 보드                          | 특징                  | Yocto        | 비고                            |
|-------------------------------|-----------------------|--------------|---------------------------------|
| **Toradex Verdin iMX8M Plus** | SoM, 산업 등급        | ✅ Kirkstone | Hailo 공식 가이드 + 레시피 완비 |
| SolidRun HummingBoard 8P      | iMX8MP + Hailo-8 키트 | ✅           | NXP-Hailo 공식 파트너십         |

- **가장 성숙한 Hailo+Yocto 통합** (NXP가 Hailo와 공식 파트너)
- 단점: Android 생태계 약함, 월패드 업체 대응 어려움
- 적합: 산업용 게이트웨이, 고신뢰 환경

### 참고: RK3568/RK3566 (월패드에선 쓰지만 비추)

- PCIe Gen2 1-lane만 지원 → Hailo-8 대역폭 부족
- 내장 NPU 0.8~1 TOPS로 AI 성능 부족
- 월패드 UI용으로는 쓰지만, AI 추론 타겟으로는 부적합

## Yocto 레이어 호환 매트릭스

### meta-hailo (Hailo Yocto 레이어)

| Yocto 버전 | HailoRT | TAPPAS | 비고 |
|------------|---------|--------|------|
| Dunfell (3.1) | ✅ | ✅ | EOL 임박 |
| **Kirkstone (4.0)** | ✅ | ✅ | **현재 가장 안정** |
| Mickledore (4.2) | ✅ | ❌ | HailoRT만 |
| **Scarthgap (5.0)** | ❌ | ❌ | **미지원 — 커뮤니티 요청 진행 중** |

### meta-rockchip (RK3588 Yocto BSP)

| Yocto 버전 | RK3588 | 비고 |
|------------|--------|------|
| Kirkstone (4.0) | ✅ | 안정 |
| **Scarthgap (5.0)** | ✅ | SOC_FAMILY 패치 적용됨 |

### 현실적 대응

```
현재 상황:
- meta-hailo: Kirkstone까지 지원 (Hailo-8 기준)
- meta-hailo Scarthgap: 미지원이나 포팅 예정 (커뮤니티 요청 활발)
- Hailo-10: 아직 Yocto 레이어 없음

대응 방안:
1. Hailo-8 + Kirkstone 조합으로 RK3588 포팅 먼저 진행 가능
2. meta-hailo Scarthgap 지원 타임라인 주시
3. 필요 시 Kirkstone→Scarthgap 포팅 자체 수행 (레시피 구조 단순)
```

## 안드로이드 월패드 연동 방안

### 한국 월패드 시장 현황

- 주요 칩: RK3568, RK3588 (Android 11/12/13)
- 업체들은 기존 Android 레퍼런스 보드 기반 개발 (레거시 유지)
- HomeAgent는 Android 전용 개발 안 함 → **연동(bridge)만 제공**

### 연동 아키텍처

```
┌─────────────────────┐     ┌─────────────────────┐
│   HomeAgent Hub     │     │  Android 월패드      │
│   (Yocto + Hailo)   │     │  (RK3588 Android)   │
│                     │     │                     │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │ Matter/Thread │  │     │  │ 월패드 앱     │  │
│  │ Zigbee (Z2M)  │  │ ←──→│  │               │  │
│  │ AI 추론       │  │MQTT │  │               │  │
│  │ (Hailo-8)     │  │/HTTP│  │               │  │
│  └───────────────┘  │     │  └───────────────┘  │
└─────────────────────┘     └─────────────────────┘
     Yocto 전담                Android 월패드 업체
```

- **MQTT/HTTP 브릿지**: 가장 현실적. 네트워크 기반, 플랫폼 무관
- **동일 보드 듀얼 OS**: RK3588에서 Linux+Android 멀티부팅 (복잡, 비추)
- **AIDL/HAL**: 같은 보드에서 Yocto→Android 서비스 호출 (고급)

## 구매/검증 우선순위

```
1. Banana Pi BPI-M7 + Hailo-8 M.2 모듈
   → Hailo 공식 문서 기반 빠른 검증
   → Yocto meta-rockchip으로 이미지 빌드
   → 가격: 보드 ~$120 + Hailo-8 모듈 ~$70 = ~$190

2. Geniatech APC3588-AI (Hailo-8 내장)
   → 산업용 평가 시 고려
   → 양산 시 ODM 협력 가능

3. Toradex Verdin iMX8M Plus (산업용 백업)
   → 고신뢰 환경 필요 시
```

## 참고 링크

- [meta-hailo GitHub](https://github.com/hailo-ai/meta-hailo)
- [meta-hailo Scarthgap 요청 스레드](https://community.hailo.ai/t/roadmap-for-hailo-8-support-meta-hailo-on-yocto-linux-5-0-scarthgap/2847)
- [meta-rockchip (JeffyCN)](https://github.com/JeffyCN/meta-rockchip)
- [Banana Pi BPI-M7 + Hailo 가이드](https://docs.banana-pi.org/en/BPI-M7/Hailo-with-bananapi)
- [Geniatech APC3588-AI 제품 페이지](https://www.geniatech.com/product/apc3588-ai/)
- [Toradex + Hailo Edge AI](https://www.toradex.com/blog/accelerating-edge-ai-hailo)
- [NXP + Hailo 파트너십](https://www.nxp.com/design/training/hailo-power-efficient-couple-deploying-hailo-8-with-nxps-processors-for-fierce-embedded-ai-platforms:TIP-CONNECTS2021-ENT522A)
- [Hailo on ARM boards (실전 테스트)](https://medium.com/@zlodeibaal/how-to-run-hailo-on-arm-boards-d2ad599311fa)

---

*조사일: 2026-02-09*
*작성: HomeAgent 프로젝트*
