# Edge/Zigbee notes for HomeAgent boundary

HomeAgent 본류는 Matter/Thread hub다. Zigbee/MQTT는 삭제하지 않지만 **HomeAgent 핵심 제어 경로가 아니라 edge/data-collection 경로**로 취급한다. 실제 ESP32/Zig 지향 작업은 `~/repos/gh/edgeagent-config`에서 진행한다.

## 결정

| 영역 | 현재 결정 |
|------|-----------|
| HomeAgent 제어 | Matter/Thread + Go REST/SSE + A2A |
| Zigbee 역할 | Matter가 커버하지 못하는 센서/데이터 수집 후보 |
| MQTT 역할 | HA autodiscovery 형식의 정제된 entity ingest 후보 |
| matterbridge | Controller가 아님. Zigbee 장치를 Matter bridge로 노출할 수는 있으나 Matter 디바이스 commissioning/control은 못함 |
| 라디오 | Thread RCP와 Zigbee NCP는 분리한다. MultiPAN은 deprecated라 기본 경로 아님 |

## 아키텍처 후보 — 보류

```text
Zigbee device → zigbee2mqtt → MQTT entity → HomeAgent Go
Matter device → OTBR/Thread → matterjs-server → HomeAgent Go
```

원칙:

- Go가 제어/판단 로직을 소유한다.
- matterjs-server는 Matter 프로토콜 엔진이다.
- zigbee2mqtt는 raw Zigbee를 HA-style entity로 증류하는 수집 계층이다.
- AI/agent는 raw frame이 아니라 `temperature=24.5`, `contact=open` 같은 의미 단위만 본다.

## zigbee2mqtt upstream 기여 최소 절차

대상 리포는 보통 `zigbee-herdsman-converters`다.

```bash
git clone https://github.com/YOUR_USERNAME/zigbee-herdsman-converters
cd zigbee-herdsman-converters
git checkout -b add-device-YOUR_DEVICE_MODEL
```

필수 수집 정보:

- `zigbeeModel`
- `manufacturerName`
- input/output cluster 목록
- attribute 목록
- 실제 동작 로그와 사진

기본 디바이스 정의 예시:

```ts
{
  zigbeeModel: ['TS0001'],
  model: 'TS0001',
  vendor: 'Tuya',
  description: 'Smart switch',
  extend: [tuya.modernExtend.tuyaOnOff()],
}
```

PR 전 체크:

```bash
npm run lint
npm run test
```

## HomeAgent에 남기는 이유

- 과거 Phase 1 Zigbee/MQTT 검증의 맥락 보존.
- 향후 edgeagent-config와 HomeAgent가 만날 때 프로토콜 경계를 잊지 않기 위함.
- 다만 새 Zig/ESP32 펌웨어 설계는 HomeAgent가 아니라 `edgeagent-config`의 책임이다.

## 흡수된 원문

MQTT/HA/Zigbee 전략과 upstream 기여 절차 원문은 이 문서로 압축 흡수했고,
빈 스텁 문서는 2026-07-24에 제거했다(git 히스토리에 보존).
