# MQTT + Home Assistant 호환 전략 — absorbed

이 문서의 현재 유효한 내용은 [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md)로 압축 흡수했다.

## 현재 결정

- HomeAgent 본류는 Matter/Thread hub다.
- Zigbee/MQTT는 제어 본류가 아니라 **edge/data-collection 후보**다.
- 실제 ESP32/Zig 지향 작업은 `~/repos/gh/edgeagent-config`에서 진행한다.
- Zigbee를 재투입한다면 `zigbee2mqtt → MQTT entity → HomeAgent Go` 형태가 기본 후보.
- Matter 디바이스는 계속 `OTBR/Thread → matterjs-server → HomeAgent Go` 경로.
- `matterbridge`는 Controller가 아니다. Zigbee 장치를 Matter bridge로 노출할 수는 있지만 Matter 디바이스 commissioning/control은 못한다.
- MultiPAN은 deprecated이므로 Thread RCP와 Zigbee NCP는 분리한다.

자세한 경계와 최소 upstream 절차는 [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md)를 본다.
