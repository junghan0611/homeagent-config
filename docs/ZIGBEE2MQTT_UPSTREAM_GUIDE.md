# zigbee2mqtt Upstream 기여 가이드 — absorbed

이 문서의 핵심 절차는 [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md)로 압축 흡수했다.

## 현재 결정

- 새 Zigbee/ESP32/edge 작업은 HomeAgent가 아니라 `~/repos/gh/edgeagent-config`에서 진행한다.
- HomeAgent에는 Zigbee를 직접 구현하지 않는다.
- 필요한 경우 zigbee2mqtt/zigbee-herdsman-converters upstream에 디바이스 정의를 기여한다.

## 최소 절차

```bash
git clone https://github.com/YOUR_USERNAME/zigbee-herdsman-converters
cd zigbee-herdsman-converters
git checkout -b add-device-YOUR_DEVICE_MODEL
```

수집할 것:

- `zigbeeModel`
- `manufacturerName`
- cluster/attribute 목록
- 실제 로그와 테스트 증거

검증:

```bash
npm run lint
npm run test
```

자세한 HomeAgent ↔ Edge/Zigbee 경계는 [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md)를 본다.
