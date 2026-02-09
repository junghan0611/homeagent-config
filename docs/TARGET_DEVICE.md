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

## AI 모델 배포 전략: GPU 클러스터 → 엣지 디바이스

> 관련 문서: `hej-nixos-cluster/MODEL_TUNING.md`, `docs/A2A.md`

### Hailo 세대별 AI 추론 능력

| 항목 | Hailo-8L (현재 개발) | Hailo-8 (양산 타겟) | Hailo-10H (차세대) |
|------|---------------------|--------------------|--------------------|
| 성능 | 13 TOPS | 26 TOPS | 50 TOPS |
| 정밀도 | INT8 | INT8/INT4 | INT4 |
| 최대 모델 크기 (INT4) | ~0.5B | ~1.5B | ~3B |
| 메모리 | 온칩 only | 온칩 only | 온칩 + 외부 |
| Yocto meta-hailo | Kirkstone ✅ | Kirkstone ✅ | 미지원 (대기) |

### 타겟별 모델 대응 매트릭스

```
┌──────────────────────────────────────────────────────────────────────┐
│                    GPU 클러스터 (3x RTX 5080)                        │
│                    QLoRA 파인튜닝 + 양자화                            │
│                                                                      │
│  Qwen3-0.6B ──→ INT4 ──→ HEF ──→ Hailo-8L / Hailo-8               │
│  Qwen3-1.5B ──→ INT4 ──→ HEF ──→ Hailo-8  / Hailo-10H             │
│  Qwen3-1.5B ──→ INT4 ──→ HEF ──→ Hailo-10H (풀 성능)              │
└──────────────────────────────────────────────────────────────────────┘
```

| 모델 | INT4 크기 | Hailo-8L | Hailo-8 | Hailo-10H | 용도 |
|------|-----------|----------|---------|-----------|------|
| **Qwen3-0.6B** | ~0.3GB | ✅ | ✅ | ✅ | Intent 파싱, 기본 A2A |
| **Qwen3-1.5B** | ~0.8GB | ❌ | ⚠️ 가능 | ✅ | Constitutional 추론, A2A 협상 |
| Phi-3-mini (3.8B) | ~2GB | ❌ | ❌ | ⚠️ 한계 | 참고용 (너무 큼) |

### Phase별 AI 기능 로드맵

```
Phase 1: Hailo-8L/8 (현재~양산)
├── Qwen3-0.6B 파인튜닝 배포
├── Intent 파싱: "거실 불 꺼줘" → structured action    ✅ 가능
├── 기본 A2A: Master Agent에 증류 데이터 전달           ✅ 가능
├── Constitutional 추론: 단순 원칙 적용                 ⚠️ 제한적
└── 복잡한 판단: Go 상태머신 + 결정론적 로직으로 보완   ✅ 전략

Phase 2: Hailo-10H (차세대)
├── Qwen3-1.5B 파인튜닝 배포
├── Constitutional 추론: 원칙 간 충돌 해석              ✅ 가능
├── A2A 협상: Master Agent와 양방향 대화                ✅ 가능
└── 컨텍스트 인식: context.json 기반 배포 환경 해석     ✅ 가능
```

### Hailo-8 시대의 A2A 전략: "분업"

Hailo-8(26 TOPS)에서 1.5B 모델은 빠듯하다. 핵심 전략은 **모델이 모든 걸 하지 않는 것**:

```
┌────────────────────────────────────────────────────────────┐
│ HomeAgent (RK3588 + Hailo-8, Yocto)                        │
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │ Qwen3-0.6B   │  │ Go 상태머신  │  │ A2A 클라이언트   │ │
│  │ (Hailo-8)    │  │ (결정론적)   │  │ (Go HTTP/SSE)    │ │
│  │              │  │              │  │                  │ │
│  │ - Intent     │  │ - 원칙 적용  │  │ - 증류 전송      │ │
│  │ - 한국어 NLU │  │ - 안전 규칙  │  │ - 에스컬레이션   │ │
│  │ - 요약 생성  │  │ - 상태 전이  │  │ - 결정 수신      │ │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘ │
│         │                 │                    │           │
│         └────────intent───┘                    │           │
│                   │                            │           │
│              action/판단                  A2A Protocol      │
│                   │                            │           │
│                   ↓                            ↓           │
│           Matter/Zigbee 제어         Master Agent (Cloud)   │
└────────────────────────────────────────────────────────────┘

역할 분담:
  LLM (Hailo)     → "무엇을 원하는지" 이해 (Intent, NLU)
  Go 상태머신     → "어떻게 행동할지" 결정 (Constitutional, 안전)
  A2A             → "혼자 못 하면" 위임 (에스컬레이션, 증류)
```

**왜 이 분업이 효과적인가:**

1. **Intent 파싱은 0.6B로 충분** — 구조화된 출력, 한정된 도메인
2. **Constitutional 판단은 Go 코드가 더 안전** — 결정론적, 감사 가능, 실패 시 예측 가능
3. **복잡한 판단은 Master Agent에 위임** — A2A escalation, 토큰 비용만 발생
4. **Hailo-10H 전환 시 LLM 영역만 확장** — 아키텍처 변경 없이 모델만 교체

### 파인튜닝 → 엣지 배포 파이프라인

```
NixOS GPU 클러스터                       Yocto 엣지 디바이스
┌─────────────────────┐                 ┌─────────────────────┐
│ gpu-01/02: 학습     │                 │ RPi5 / RK3588       │
│  QLoRA 파인튜닝     │                 │                     │
│  (Qwen3-0.6B)      │                 │  HailoRT 추론       │
│        │            │                 │  Go HomeAgent       │
│        ↓            │    SCP/NFS      │  Node.js 프로토콜   │
│ gpu-03: 양자화      │ ──────────────→ │                     │
│  PyTorch→ONNX→HEF  │   .hef 파일     │  .hef 모델 로드     │
│        │            │                 │                     │
│        ↓            │                 │  추론 검증          │
│ 벤치마크 평가       │                 │  Intent 정확도 측정 │
└─────────────────────┘                 └─────────────────────┘

배포 산출물:
  homeagent-intent-v1.hef     (Intent 파싱 모델, ~0.3GB)
  homeagent-summary-v1.hef    (증류 요약 모델, ~0.3GB)
  → Yocto 레시피로 이미지에 포함
```

### 타겟 디바이스별 AI 구성 요약

| 구성 | RPi5 + Hailo-8L | RK3588 + Hailo-8 | RK3588 + Hailo-10H |
|------|-----------------|-------------------|---------------------|
| 단계 | Phase 1 (개발) | Phase 2 (양산) | Phase 2+ (차세대) |
| 모델 | Qwen3-0.6B | Qwen3-0.6B | Qwen3-1.5B |
| Intent 파싱 | ✅ | ✅ | ✅ |
| 증류 요약 | ✅ | ✅ | ✅ |
| Constitutional 추론 | Go 상태머신 | Go 상태머신 | **LLM + Go 하이브리드** |
| A2A 에스컬레이션 | ✅ | ✅ | ✅ (자율 협상) |
| 총 AI 성능 | 13 TOPS | 32 TOPS (NPU+Hailo) | 56 TOPS (NPU+Hailo) |

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
