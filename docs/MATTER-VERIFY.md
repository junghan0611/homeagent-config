# Matter 검증 기록

chip-tool(oracle)과 matterjs-server를 동일 디바이스에 대해 비교하며 검증하는 문서.

## 검증 전략

```
chip-tool (oracle, CLI)              matterjs-server (검증 대상, WebSocket)
├── commissioning ✅ (2026-02-09)     ├── commissioning ✅ (2026-02-23)
├── attribute read ✅                  ├── attribute read ✅
├── (데몬 모드 없음)                   ├── start_listening → 이벤트 스트리밍 ✅
└── 결과 = ground truth               └── 결과 비교 → 100% 일치 ✅

Go HomeAgent v0.5.1 — 단일 바이너리로 전체 스택 통합
├── Matter WS 클라이언트 (단일 ReadLoop 아키텍처)
├── Hub 코디네이터 (상태관리, SSE 브로드캐스트)
├── REST API (devices, commission, command, events)
├── Lit 프론트엔드 (대시보드, 페어링, On/Off 제어)
└── 자동 Thread dataset + WiFi credentials 주입
```

**원칙**: chip-tool에서 되는 것이 matterjs-server에서도 동일하게 동작해야 한다.
불일치 발생 시 chip-tool 결과를 기준으로 matterjs-server 쪽을 디버깅.

---

## 환경

| 항목 | 값 |
|------|-----|
| RPi5 IP | 192.168.69.6 |
| Thread 상태 | leader (otbr-thread-init 자동) |
| SRP 상태 | running (otbr-srp-enable 자동) |
| Spinel URL | `spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800` |
| Node.js | Yocto 이미지 내장 (v20.18.2) |
| matterjs-server | 0.3.5 (matter.js/0.16.9-alpha.0-20260204) |
| homeagent | v0.5.1 (Go, aarch64 정적 바이너리) |
| UI | Lit WebComponents (Vite 빌드) |

## 테스트 디바이스

| 디바이스 | Setup Code | Node ID | 프로토콜 | 타입 | 상태 |
|----------|-----------|---------|---------|------|------|
| Tuya 도어센서 #1 (DS001-T) | `0239-244-2173` | 1 | Thread | contact_sensor | ✅ 동작 |
| Tuya 도어센서 #2 (DS001-T) | `0073-043-4300` | 7 | Thread | contact_sensor | ✅ 동작 |
| Tapo Mini Smart Wi-Fi Plug | `0564-154-0754` | 8 | WiFi | on_off_plug | ✅ 동작 |

---

## Phase 1: chip-tool Oracle 기준값 (2026-02-09 검증 완료)

### Commissioning

```bash
# RPi5에서 실행
/opt/chip-tool/run-chip-tool.sh pairing code-thread 1 \
  hex:<dataset> 0073-043-4300 \
  --bypass-attestation-verifier true
```

흐름: BLE → PASE → NOC → Thread → SRP → mDNS → CASE → CommissioningComplete

### Attribute Read

```bash
/opt/chip-tool/run-chip-tool.sh booleanstate read state-value 1 1
# 결과: Ok: value: FALSE
```

| 항목 | 값 |
|------|-----|
| 클러스터 | BooleanState (0x0045) |
| 어트리뷰트 | StateValue (0x0000) |
| 엔드포인트 | 1 |
| 노드 ID | 1 |
| 결과 | FALSE (문 닫힘) |

### 알려진 제약

- `--bypass-attestation-verifier true` 필수 (DAC 검증 실패)
- chip-tool은 CLI 도구 — 데몬 모드 없음, 지속 구독 불가
- fabric 데이터: `/tmp/chip_tool_kvs` (기본)

---

## Phase 2: matterjs-server 검증 (2026-02-23 완료 ✅)

### 2-1. Yocto 빌드

| 항목 | 상태 | 비고 |
|------|:----:|------|
| 레시피 (.bb) | ✅ | `matterjs-server_0.3.5.bb` |
| bbappend | ✅ | systemd + 환경변수 |
| npm-shrinkwrap | ✅ | 176개 패키지, `@matter/main` 0.16.9-alpha |
| bitbake 빌드 | ✅ | prebuild QA 해결 (9e5aef1) |
| RPi5 서비스 기동 | ✅ | active (running), :5580 리스닝 |

### 2-2. 서비스 기동 검증 (✅)

```bash
systemctl status matterjs-server   # active (running)
journalctl -u matterjs-server      # WebServer listening on http://0.0.0.0:5580
```

- 대시보드: http://192.168.69.6:5580
- BLE: `--bluetooth-adapter 0` 옵션으로 활성화 필요 (기본 비활성)

### 2-3. Commissioning 비교 (✅)

**chip-tool (oracle)** — 2026-02-23 06:05 UTC:
```bash
/opt/chip-tool/run-chip-tool.sh pairing code-thread 1 \
  hex:0e08...f7f8 0239-244-2173 \
  --bypass-attestation-verifier true
# → "Device commissioning completed with success"
```

**matterjs-server (WebSocket)** — 2026-02-23 06:12 UTC:
```json
{"message_id": "commission", "command": "commission_with_code", "args": {"code": "0239-244-2173"}}
```
결과: `"node_id": 1, "available": true`

| 비교 항목 | chip-tool | matterjs-server | 일치 |
|----------|-----------|-----------------|:----:|
| Commissioning 성공 | ✅ | ✅ | ✅ |
| Node ID 할당 | 1 | 1 | ✅ |
| Thread 조인 확인 | ✅ | ✅ | ✅ |
| VendorName | Tuya | Tuya | ✅ |
| ProductName | Door Window Sensor_Thread | Door Window Sensor_Thread | ✅ |

### 2-4. Attribute Read 비교 (✅)

**chip-tool (oracle)**:
```bash
/opt/chip-tool/run-chip-tool.sh booleanstate read state-value 1 1
# → Endpoint: 1 Cluster: 0x0000_0045 Attribute 0x0000_0000
#   StateValue: FALSE
```

**matterjs-server (commissioning 응답에 포함)**:
```json
"1/69/0": false
```

(attribute_path: endpoint/cluster/attribute = 1/0x0045(=69)/0x0000)

| 비교 항목 | chip-tool | matterjs-server | 일치 |
|----------|-----------|-----------------|:----:|
| BooleanState (닫힘) | FALSE | false | ✅ |
| DeviceType | 21 (Contact Sensor) | 21 | ✅ |
| Endpoint | 1 | 1 | ✅ |
| VendorID | 4701 (0x125D) | 4701 | ✅ |
| Battery (0/47/11) | - | 3300 mV | ✅ |
| Matter Version | - | 1.2.0 | ✅ |

### 2-5. 이벤트 구독 (✅ — chip-tool에 없는 기능)

```json
{"message_id": "listen", "command": "start_listening"}
```

도어 센서 개폐 시 실시간 이벤트 수신 확인:

```
06:12:35 UTC → {"event":"attribute_updated","data":[1,"1/69/0",true]}   # 문 열림
06:12:38 UTC → {"event":"attribute_updated","data":[1,"1/69/0",false]}  # 문 닫힘
06:12:39 UTC → {"event":"attribute_updated","data":[1,"1/69/0",true]}   # 문 열림
06:12:40 UTC → {"event":"attribute_updated","data":[1,"1/69/0",false]}  # 문 닫힘
```

**결론**: matterjs-server의 `start_listening`은 chip-tool에 없는 핵심 기능.
WebSocket을 통해 실시간 도어 개폐 이벤트를 안정적으로 수신함.

### Phase 2 최종 결론

> **matterjs-server는 chip-tool oracle과 100% 일치하며, 추가로 실시간 이벤트 구독 기능을 제공한다.**
> chip-tool은 디버깅 도구로만 유지하고, 운영은 matterjs-server 기반으로 진행.

---

## Phase 3: Go 컨트롤러 + Lit 프론트엔드 (2026-02-23 완료 ✅)

### 3-1. Go HomeAgent 컨트롤러

| 항목 | 상태 | 비고 |
|------|:----:|------|
| Matter WS 클라이언트 | ✅ | 단일 ReadLoop + pending channel 디스패처 |
| Hub 코디네이터 | ✅ | DeviceState 관리, 이벤트 브로드캐스트 |
| REST API | ✅ | /api/devices, /api/commission, /api/devices/command, /api/events |
| Thread dataset 자동 주입 | ✅ | ot-ctl → set_thread_dataset |
| WiFi credentials 주입 | ✅ | HOMEAGENT_WIFI_SSID 환경변수 |
| 자동 재연결 | ✅ | WS 끊기면 5초 후 재연결 |
| 정적 파일 서빙 | ✅ | HOMEAGENT_UI_DIR |

### 3-2. 멀티 디바이스 커미셔닝 (✅)

matterjs-server `--bluetooth-adapter 0` + `set_thread_dataset` + `set_wifi_credentials`
설정 후 BLE → Thread/WiFi 페어링 동작 확인.

| 순서 | 디바이스 | 경로 | 결과 |
|:----:|----------|------|:----:|
| 1 | Tuya 도어센서 #1 | BLE → Thread | ✅ Node 1 |
| 2 | Tuya 도어센서 #2 | BLE → Thread | ✅ Node 7 |
| 3 | Tapo WiFi 플러그 | BLE → WiFi | ✅ Node 8 |

**필수 설정** (없으면 페어링 실패):
```
--bluetooth-adapter 0    # BLE 디스커버리 활성화
set_thread_dataset       # Thread 네트워크 합류용
set_wifi_credentials     # WiFi 디바이스 연결용
```

### 3-3. On/Off 디바이스 제어 (✅)

```bash
# device_command API (matterjs-server WS)
# OnOff cluster = 6, command_name = "on" / "off" / "toggle"
POST /api/devices/command
{"node_id": 8, "command": "on"}   → 플러그 켜짐
{"node_id": 8, "command": "off"}  → 플러그 꺼짐
```

| 비교 항목 | 안드로이드 앱 | HomeAgent Web | 비고 |
|----------|:-----------:|:------------:|------|
| Thread 페어링 | ✅ | ✅ | 동일 |
| WiFi 페어링 | ✅ | ✅ | 동일 |
| 실시간 이벤트 | ❌ | ✅ | SSE 스트리밍 |
| On/Off 제어 | ❌ | ✅ | device_command |
| 멀티 디바이스 | ❌ | ✅ | 3대 동시 |
| 개발 속도 | 수주 | 수시간 | Go+Lit vs Kotlin+Compose |

### 3-4. Lit 프론트엔드 (✅)

```
http://192.168.69.6:8080/
├── 대시보드 (ha-app)
│   ├── 에이전트 메시지바 (상태/에러 표시)
│   ├── 디바이스 카드 (ha-device-card)
│   │   ├── contact_sensor: 열림/닫힘 + 아이콘
│   │   └── on_off_plug: 켜짐/꺼짐 + 토글 스위치
│   ├── 실시간 이벤트 로그 (SSE)
│   └── 페어링 다이얼로그 (ha-commission-dialog)
└── SSE /api/events → 상태 변경 즉시 반영
```

### 3-5. 아키텍처 결정 사항

**단일 ReadLoop 패턴** (v0.4.0):
- 이전: GetNodes, Commission, Listen이 각각 ReadJSON → 메시지 경합 → 크래시
- 이후: 단일 ReadLoop 고루틴이 모든 WS 메시지 읽기 → pending channel로 디스패치
- 효과: 커미셔닝 중에도 이벤트 수신 유지, hub 크래시 방지

**비동기 Commission** (v0.3.1):
- POST /api/commission → 202 즉시 응답
- 결과는 SSE event로 device_added / commission_error 전달
- 60~120초 소요되는 BLE 커미셔닝에서 브라우저 타임아웃 방지

---

## 트러블슈팅 기록

### BLE disabled (2026-02-23)

**증상**: `No device discovered using identifier {"shortDiscriminator":0}`
**원인**: matterjs-server 기본 설정에서 BLE 비활성
**해결**: systemd 서비스에 `--bluetooth-adapter 0` 추가

### Thread credentials not set (2026-02-23)

**증상**: `No Wi-Fi/Thread network credentials are configured`
**원인**: matterjs-server가 Thread dataset을 모름
**해결**: Go 컨트롤러 시작 시 `ot-ctl dataset active -x` → `set_thread_dataset` 자동 주입

### WS 메시지 경합 크래시 (2026-02-23)

**증상**: 커미셔닝 시작 → 2분 후 hub 프로세스 종료
**원인**: CommissionWithCode와 Listen이 같은 WS conn에서 동시 ReadJSON
**해결**: 단일 ReadLoop + pending channel 디스패처 아키텍처

### SSE 재연결 무한 루프 (2026-02-23)

**증상**: Firefox 메모리 폭주
**원인**: EventSource 에러 시 이전 연결 안 닫고 3초마다 새로 생성
**해결**: close 후 재연결 + exponential backoff + 최대 10회 제한

### SED (Sleepy End Device) 타임아웃

도어센서는 Thread SED로 동작. chip-tool의 `open-commissioning-window`가
디바이스 슬립 시 타임아웃 (20초) 발생.

**해결**: 센서 물리 조작으로 웨이크업 후 명령 전송, 또는
matterjs-server 단독 커미셔닝 (팩토리 리셋 후 직접 commission_with_code).

### Commissioning Window Error 0x02

`open-commissioning-window` 재실행 시 `Cluster-specific error: 0x02` 발생.
이미 창이 열려있는 상태. `revoke-commissioning` 후 재시도로 해결.

---

## 참고

- [matterjs-server GitHub](https://github.com/matter-js/matterjs-server)
- [matter.js SDK](https://github.com/matter-js/matter.js) (v0.16.9-alpha.0-20260204)
- 소스 클론: `~/repos/3rd/matterjs-server`, `~/repos/3rd/matter.js`
- chip-tool 빌드/배포: [HOWTO.md](../HOWTO.md#8-matter-commissioning-chip-tool)
- Matter 아키텍처: [MQTT-HA.md](MQTT-HA.md)

> 로드맵은 [README.md](../README.md#로드맵) 참조.
