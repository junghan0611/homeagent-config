# HomeAgent 설치 가이드 — absorbed

이 문서의 Android/RK3576 설치 절차는 [`../HOWTO.md`](../HOWTO.md)의 **Android/RK3576 호환성 검증 요약** 섹션으로 압축 흡수했다. Android는 메인 지원 배포가 아니라 검증/호환성 경로다.

## 현재 기준

- RPi5 클린 빌드/플래시/재현 절차: [`../HOWTO.md`](../HOWTO.md)
- Android/RK3576 호환성 검증 요약: [`../HOWTO.md`](../HOWTO.md#9-androidrk3576-호환성-검증-요약)
- Flutter 구조: [`FLUTTER.md`](FLUTTER.md)
- 플랫폼 차이: [`PLATFORM-MATRIX.md`](PLATFORM-MATRIX.md)
- Matter BLE 경계: [`MATTER.md`](MATTER.md)

## 핵심 명령

```bash
nix develop .#dev --impure
./run.sh android deploy
./run.sh android status
./run.sh android logs
./run.sh android thread-start
```

## 핵심 주의

- Android는 `--impure` devShell이 필요하다.
- 배포 대상은 `/data/local/tmp/` 아래: `homeagent`, `ui/dist/`, `nodejs-bundle/`, `otbr/`, `aliases.json`.
- Thread RCP는 RK3576 기준 `/dev/ttyS5`, 460800.
- Android BLE는 서버/matterjs가 직접 소유하지 않는다. Flutter/Android BLE API가 provisioning을 맡고, matterjs는 on-network commissioning을 맡는다.
