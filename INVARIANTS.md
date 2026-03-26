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

### K-4: MethodChannel result는 한 번만 — 가드 변수 필수

**위반 패턴**:
```kotlin
override fun onPairingComplete(errorCode: Long) {
    if (errorCode != 0L) result.error(...)  // 1번째 호출
}
override fun onCommissioningComplete(nodeId: Long, errorCode: Long) {
    result.error(...)  // 2번째 호출 → IllegalStateException crash
}
```

**문제**: CHIP SDK `CompletionListener`는 `onPairingComplete` → `onCommissioningComplete` → `onError` 순서로 여러 콜백을 호출할 수 있다. MethodChannel `result`는 한 번만 사용 가능 — 두 번 호출하면 **앱 크래시**.

**규칙**: `var resultSent = false` 가드로 첫 번째 호출만 허용.
```kotlin
var resultSent = false
fun sendOnce(block: () -> Unit) {
    if (!resultSent) { resultSent = true; block() }
}
```

---

### K-5: SDK 콜백 입력 — Kotlin에서도 검증 (Dart assert는 release에서 무시)

**위반 패턴**:
```kotlin
val ssid = call.argument<String>("ssid") ?: ""     // 빈 문자열 허용
val nodeId = call.argument<Number>("nodeId")?.toLong() ?: 1L  // 기본값 1
val bytes = hex.chunked(2).map { it.toInt(16).toByte() }     // 비hex → crash
```

**문제**: Dart `assert(ssid.isNotEmpty)`는 release APK에서 컴파일러가 제거. Kotlin이 마지막 방어선.

**규칙**:
- 필수 파라미터 null/빈값 → `result.error("INVALID_ARGS", ...)` + return
- `?: 기본값` 금지 (특히 nodeId ?: 1L — 다른 디바이스를 조작)
- 문자열 파싱은 try-catch 래핑

---

### K-6: GATT onConnectionStateChange — 실패 시 result.error 보장

**위반 패턴**: `status != 0 && status != 133` (예: 8=timeout, 19=disconnect) 일 때 `wrappedCallback`에 전달만 하고 끝. SDK가 `CompletionListener` 콜백을 호출하지 않으면 `result`가 반환 안 됨 → Flutter 120초 타임아웃까지 무한 대기.

**규칙**: `newState == STATE_DISCONNECTED && status != GATT_SUCCESS` 일 때, SDK 콜백을 기다리지 말고 **직접** `result.error("GATT_FAILED", "status=$status")` 호출 (K-4 가드와 함께 사용).

---

### K-7: BleManager removeConnection — GATT close하는 모든 곳에서 호출

**위반 패턴**:
```kotlin
// GATT 133 재시도
gatt?.close()                                    // OS 레벨 닫음
// ← removeConnection(bleConnectionId) 빠짐!     // BleManager에 좀비 남음
val newGatt = device.connectGatt(...)
bleConnectionId = platform.bleManager.addConnection(newGatt)  // 새 연결 추가

// onNotifyChipConnectionClosed
bleGatt?.close()                                 // OS 레벨 닫음
// ← removeConnection(connId) 빠짐!              // BleManager에 좀비 남음
```

**규칙**: `gatt.close()` 호출 시 반드시 `bleManager.removeConnection(connId)` 동반. `cleanupBle()`를 유일한 GATT 정리 경로로 통일하고, GATT 133 재시도와 `onNotifyChipConnectionClosed`에서도 동일 패턴 적용.

---

### K-8: SDK 타임아웃 정합 — Kotlin과 Dart가 같은 값

**위반 패턴**:
```kotlin
ctrl.setDeviceAttestationDelegate(600) { ... }  // 600초
```
```dart
static const _pairTimeout = Duration(seconds: 120);  // 120초
```

**문제**: Dart가 120초에 타임아웃으로 돌아가도 SDK attestation이 600초까지 백그라운드 실행 → BLE 리소스 점유 → 다음 pairDevice 충돌.

**규칙**: `DeviceAttestationDelegate` 타임아웃 = Dart `_pairTimeout` 이하. Dart 타임아웃 발동 시 SDK도 정리되어야 함.

---

## 테스트 사각지대 — 왜 Kotlin 버그를 못 잡는가

```
Dart 테스트 ←── mock ──→ MethodChannel ←→ Kotlin (ChipBridge.kt)
    ✅ 12개                  경계            ❌ 0개
```

**Mock Wall**: Dart 테스트는 MethodChannel을 mock하여 Kotlin 레이어를 "항상 정상 반환"으로 치환. K-1~K-8의 모든 버그는 mock 뒤에 숨어 있어 Dart 테스트로 발견 불가.

**Kotlin unit test 불가**: CHIP SDK AAR은 네이티브 라이브러리(`libCHIPController.so`), `BluetoothGatt`는 Android OS 객체 — JUnit 단독으로 mock 불가.

**대응 전략**: 테스트가 커버 못 하면 **코드가 스스로를 검증**해야 한다.
- K-4 (result 가드), K-5 (입력 검증), K-6 (GATT 실패 처리)는 **방어 코드로 내장**
- 크래시/무한대기를 "에러 메시지 + 정상 종료"로 전환
- 로그(`Log.w`)로 이상 상태 기록 → `adb logcat`에서 사후 분석 가능

---

### D-6: HTTP 응답 상태 코드 — 확인 없이 진행 금지

**위반 패턴**:
```dart
final response = await request.close();
await response.drain();
// statusCode 체크 없이 성공으로 간주
```

**문제**: Go 서버가 400/500 반환해도 Dart가 성공으로 처리 → 명령이 안 먹혀도 UI에 에러 표시 없음.

**규칙**: `_get`/`_post`/`_delete` 헬퍼에서 `statusCode >= 400`이면 `HttpException` throw. 호출부에서 catch하여 사용자에게 피드백.

---

### D-7: 명령 실패 — 사용자에게 피드백

**위반 패턴**:
```dart
}).catchError((e) {
  debugPrint('[Dashboard] command error: $e');  // 로그만
});
```

**규칙**: 사용자 인터랙션(명령, 삭제 등) 실패 시 `SnackBar`로 에러 표시. `debugPrint`는 개발자용 — 사용자는 안 봄.

---

### D-8: catch (_) {} — 완전 무음 금지

**위반 패턴**:
```dart
} catch (_) {}  // 에러 삼킴
```

**규칙**: 최소 `catch (e) { debugPrint('...: $e'); }`. 완전 무음은 디버깅 불가. `healthCheck`처럼 실패가 정상인 경우에도 로그는 남겨야 네트워크 문제 추적 가능.

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

### G-3: 디바이스 명령 값 범위 검증

**위반 패턴**: `level=999`가 Matter 디바이스에 직접 전송 → 디바이스 거부 또는 예측 불가.

**규칙**: `handleDeviceCommand`에서 값 범위 체크 후 400 반환.

| 필드 | 범위 | Matter spec |
|------|------|-------------|
| `level` | 0-254 | 0x00-0xFE |
| `hue` | 0-254 | 0x00-0xFE |
| `saturation` | 0-254 | 0x00-0xFE |
| `color_temp` | 153-500 | mireds (2000K-6535K) |

---

## 사고 기록 (Incident Log)

새 인바리언트가 필요해지는 건 보통 사고 후다. 여기에 기록하고 위 섹션에 규칙을 추가한다.

| 날짜 | 커밋 | 사고 | 추가된 규칙 |
|------|------|------|------------|
| 2026-03-26 | 6ecfa43 | OpenCommissioningCallback deviceId를 PIN으로 오인 | K-3 |
| 2026-03-26 | 9d2024c | pin_code ↔ setup_pin_code 필드명 불일치 | G-2 |
| 2026-03-26 | 155b744 | commission-on-network SSE device_added 누락 | G-1 |
| 2026-03-26 | 155b744 | BLE GATT 미정리 → connection in use | K-1 |
