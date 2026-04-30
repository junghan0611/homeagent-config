# Matter 커미셔닝 검증 기록 — absorbed

이 문서의 핵심 결과는 [`MATTER.md`](MATTER.md)의 **Android commissioning verification — BLE boundary** 섹션으로 흡수했다.

## 핵심 결론

- RK3576 Android 15에서 matterjs-server + Go homeagent + mDNS + WiFi credentials 설정은 동작한다.
- Android BT HAL은 BlueZ/HCI를 커널에 노출하지 않으므로 noble 기반 BLE 커미셔닝은 직접 동작하지 않는다.
- 따라서 Android에서는 Flutter/Android BLE API가 공장초기화 디바이스의 BLE provisioning을 맡고, matterjs-server는 이후 on-network commissioning을 맡는다.
- RPi5 Linux/Yocto에서는 BlueZ HCI가 있으므로 matterjs BLE 직접 경로가 가능하다.

## 주의 메모

- 실패한 경로: `--bluetooth-adapter 0` on Android, 직접 `hciattach`, Android BT HAL 중지.
- Thread UART는 `/dev/ttyS5`, 460800. Android Thread HAL은 OTBR 시작 전에 중지해야 한다.
- BT UART는 `/dev/ttyS4`였으나 HomeAgent 서버 경로에서는 직접 소유하지 않는다.
