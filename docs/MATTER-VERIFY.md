# Matter 검증 기록

chip-tool(oracle)과 matterjs-server를 동일 디바이스에 대해 비교하며 검증하는 문서.

## 검증 전략

```
chip-tool (oracle, CLI)              matterjs-server (검증 대상, WebSocket)
├── commissioning ✅ (2026-02-09)     ├── commissioning (검증 예정)
├── attribute read ✅                  ├── attribute read (검증 예정)
├── (데몬 모드 없음)                   ├── start_listening → 이벤트 스트리밍
└── 결과 = ground truth               └── 결과 비교 → 일치하면 통과
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

## 테스트 디바이스

| 디바이스 | Setup Code | Node ID | 클러스터 | 상태 |
|----------|-----------|---------|---------|------|
| Tuya 도어센서 (DS001-T) | `0239-244-2173` | 1 | BooleanState (0x0045) | 동작 확인 |

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
- BLE 미지원 (`ENODEV`) — Thread(mDNS) 기반 커미셔닝만 가능

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

> 참고: matterjs-server는 `set_thread_operational_dataset` 명령이 없음.
> Thread dataset은 BLE commissioning 과정에서 자동으로 전달됨.

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
06:12:42 UTC → {"event":"attribute_updated","data":[1,"1/69/0",true]}   # 문 열림
06:12:43 UTC → {"event":"attribute_updated","data":[1,"1/69/0",false]}  # 문 닫힘
06:13:04 UTC → {"event":"attribute_updated","data":[1,"1/69/0",true]}   # 문 열림
```

**결론**: matterjs-server의 `start_listening`은 chip-tool에 없는 핵심 기능.
WebSocket을 통해 실시간 도어 개폐 이벤트를 안정적으로 수신함.

### Phase 2 최종 결론

> **matterjs-server는 chip-tool oracle과 100% 일치하며, 추가로 실시간 이벤트 구독 기능을 제공한다.**
> chip-tool은 디버깅 도구로만 유지하고, 운영은 matterjs-server 기반으로 진행.

---

## Phase 3: Go 컨트롤러 연동 (다음 단계)

matterjs-server WebSocket API → Go 컨트롤러 → MQTT 브리지 구조.

| 작업 | 상태 | 비고 |
|------|:----:|------|
| WebSocket 클라이언트 (Go) | 미시작 | `start_listening` 구독 |
| MQTT 퍼블리시 | 미시작 | `homeagent/matter/1/contact` |
| 상태 머신 | 미시작 | 디바이스 온라인/오프라인 관리 |

---

## 트러블슈팅 기록

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
