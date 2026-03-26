# 인바리언트 체크 가이드

> AGENTS.md의 인바리언트 테이블은 **아키텍처 금지 규칙** (뭘 하지 말 것).
> 이 문서는 **런타임 검증 규칙** (코드가 지켜야 할 불변 조건 + 체크 방법).
>
> 새 기능/버그 수정 시 해당 언어 섹션을 읽고, 위반 가능성을 코드에서 확인한다.

---

## Dart (Flutter)

### D-1: MethodChannel 반환값 — 기본값 금지, 실패를 드러내라

**위반 패턴** (면피 코드):
```dart
setupPinCode: (result?['setupPinCode'] as num?)?.toInt() ?? 0,
```

**문제**: SDK가 값을 못 주면 0으로 진행 → Go 서버 400 → 사용자는 "핸드오프 실패"만 봄. 디버깅 불가.

**규칙**: MethodChannel 결과에서 필수 필드가 null/0이면 `throw`. 기본값(`?? 0`, `?? ''`)은 **선택적 필드에만** 사용.

```dart
// ✅ 올바른 패턴
final pin = (result?['setupPinCode'] as num?)?.toInt();
if (pin == null || pin == 0) {
  throw PlatformException(code: 'INVALID_PIN', message: 'SDK returned pin=$pin');
}
```

**적용 대상**: `chip_controller.dart`의 `pairDevice`, `openCommissioningWindow` 반환값.

---

### D-2: HttpClient — 생성하면 닫아라

**위반 패턴**:
```dart
final client = HttpClient();
final request = await client.postUrl(...);
// ... response 처리 ...
// client.close() 없음 ← 소켓 누수
```

**규칙**: 단발성 HTTP 요청은 반드시 `client.close()`. 또는 클래스 레벨에서 하나 만들어 재사용.

**적용 대상**: `chip_commissioning.dart`의 `_requestHandoff`, `_setServerWifiCredentials`, `_loadThreadDataset`.

---

### D-3: SSE 파싱 — string contains 금지, JSON decode 사용

**위반 패턴**:
```dart
if (data.contains('device_added')) { ... }
```

**문제**: 디바이스 이름이나 에러 메시지에 `device_added` 문자열 포함 시 오탐. 같은 프로젝트의 `api_client.dart`는 제대로 JSON decode 하고 있음.

**규칙**: SSE `data:` 라인은 `jsonDecode` → `type` 필드 비교. `SseEvent.fromJson` 재사용.

---

### D-4: 비동기 체인 — 선행 조건 검증 후 진행

**위반 패턴**:
```dart
await step1();  // 실패해도 예외 안 던짐
await step2();  // step1 결과에 의존하는데 검증 없이 진행
```

**규칙**: 커미셔닝처럼 다단계 체인에서 각 단계의 결과를 검증.

| 단계 | 선행 조건 | 체크 |
|------|-----------|------|
| `pairDevice` | BLE on, SDK init | `_chipReady` 확인 ✅ (있음) |
| `openCommissioningWindow` | `commResult.success == true` | ✅ (있음) |
| `_requestHandoff` | `setupPinCode > 0` | ❌ **없음 — 추가 필요** |
| Thread 커미셔닝 | dataset hex 로드 완료 | ❌ **없음 — 추가 필요** |

---

### D-5: 타임아웃 — 무한 대기 금지

**위반 패턴**:
```dart
await _channel.invokeMethod('pairDevice', args);  // 타임아웃 없음
```

**문제**: BLE 스캔 실패, SDK hang 시 UI가 영원히 "진행 중...".

**규칙**: 60초+ 걸릴 수 있는 MethodChannel 호출은 `.timeout(Duration(...))` 래핑. 타임아웃 시 사용자에게 "시간 초과" 안내 + BLE 정리.

---

## Kotlin (Android Native — ChipBridge)

### K-1: BLE GATT — 열면 반드시 닫아라 (cleanupBle)

**위반 패턴**: GATT connect 후 `onCommissioningComplete`에서 닫지 않음 → 다음 pairDevice 시 "connection already in use".

**규칙**: `cleanupBle()`는 3곳에서 호출 보장:
1. `onCommissioningComplete` (성공/실패 모두)
2. `pairDevice` 시작 전 (이전 잔여 정리)
3. `dispose()` (화면 종료)

`AndroidBleManager.removeConnection(connId)` 반드시 포함 — OS GATT close만으로 부족.

---

### K-2: CompletionListener — 모든 콜백에서 result 반환

**위반 패턴**: `onError` 콜백에서 `result.error()` 호출 안 하면 Flutter 쪽 `await`가 영원히 대기.

**규칙**: `CompletionListener`의 `onCommissioningComplete`, `onPairingComplete`, `onError` 모두 `result.success()` 또는 `result.error()` 호출 보장.

---

### K-3: OpenCommissioningCallback — 파라미터 의미 확인

**사고 기록**: `onSuccess(long deviceId, String manualCode, String qrCode)` — 첫 파라미터가 `deviceId`인데 `setupPinCode`로 오인하여 PIN 불일치 발생 (6ecfa43에서 수정).

**규칙**: CHIP SDK 콜백 파라미터명이 모호하면 **SDK 소스(GitHub)에서 인터페이스 정의 확인**. `javap`으로 시그니처만 보면 `long`이 뭔지 알 수 없다.

---

## Go (서버)

### G-1: goroutine에서 상태 변경 시 — 이벤트 발행 잊지 마라

**사고 기록**: `handleCommissionOnNetwork` goroutine에서 `addNode` 후 `device_added` SSE 이벤트를 안 보냄 → Flutter가 완료를 감지 못함 (155b744에서 수정).

**규칙**: `addNode()` 호출 후 반드시 `eventCh <- Event{Type: "device_added", ...}`. `Commission()` 함수를 레퍼런스로 삼는다.

---

### G-2: REST ↔ WS 필드명 변환 — 매핑 테이블 유지

**사고 기록**: Flutter→Go는 `pin_code`, Go→python-matter-server는 `setup_pin_code`. 필드명 불일치로 400 에러 (9d2024c에서 수정).

**규칙**: REST API 필드명(외부)과 WS 필드명(내부)이 다른 경우, 변환 지점을 주석으로 명시.

| REST (외부) | WS (내부) | 변환 위치 |
|------------|-----------|-----------|
| `pin_code` | `setup_pin_code` | `hub.go` → `client.go` |
| `ip_addr` | `ip_addr` | 동일 (변환 없음) |

---

## 사고 기록 (Incident Log)

새 인바리언트가 필요해지는 건 보통 사고 후다. 여기에 기록하고 위 섹션에 규칙을 추가한다.

| 날짜 | 커밋 | 사고 | 추가된 규칙 |
|------|------|------|------------|
| 2026-03-26 | 6ecfa43 | OpenCommissioningCallback deviceId를 PIN으로 오인 | K-3 |
| 2026-03-26 | 9d2024c | pin_code ↔ setup_pin_code 필드명 불일치 | G-2 |
| 2026-03-26 | 155b744 | commission-on-network SSE device_added 누락 | G-1 |
| 2026-03-26 | 155b744 | BLE GATT 미정리 → connection in use | K-1 |
