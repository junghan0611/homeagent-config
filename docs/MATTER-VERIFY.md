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
| RPi5 IP | 192.168.69.5 |
| Thread 상태 | leader (otbr-thread-init 자동) |
| SRP 상태 | running (otbr-srp-enable 자동) |
| Spinel URL | `spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800` |
| Node.js | Yocto 이미지 내장 (v20+) |

## 테스트 디바이스

| 디바이스 | Setup Code | Node ID | 클러스터 | 상태 |
|----------|-----------|---------|---------|------|
| Eve 도어센서 | `0073-043-4300` | 1 | BooleanState | FALSE (문 닫힘) |

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

## Phase 2: matterjs-server 검증 (진행 중)

### 2-1. Yocto 빌드

| 항목 | 상태 | 비고 |
|------|:----:|------|
| 레시피 (.bb) | ✅ | `matterjs-server_0.3.5.bb` |
| bbappend | ✅ | systemd + 환경변수 |
| npm-shrinkwrap | ✅ | 176개 패키지, `@matter/main` 0.16.9-alpha |
| bitbake 빌드 | 미검증 | `bb-cmd -c cleansstate matterjs-server` → `bb` |
| RPi5 서비스 기동 | 미검증 | `systemctl status matterjs-server` |

### 2-2. 서비스 기동 검증

```bash
# RPi5에서 확인
systemctl status matterjs-server
journalctl -u matterjs-server -f

# WebSocket 포트 확인
ss -tlnp | grep 5580
```

기대 결과:
- matterjs-server active (running)
- WebSocket :5580 리스닝
- 대시보드: http://192.168.69.5:5580

### 2-3. Commissioning 비교

**chip-tool (oracle)**:
```bash
chip-tool pairing code-thread 1 hex:<dataset> 0073-043-4300 --bypass-attestation-verifier true
```

**matterjs-server (WebSocket)**:
```json
{
  "message_id": "1",
  "command": "commission_with_code",
  "args": {
    "code": "0073-043-4300",
    "thread_dataset": "<hex dataset>"
  }
}
```

| 비교 항목 | chip-tool | matterjs-server | 일치 |
|----------|-----------|-----------------|:----:|
| Commissioning 성공 | ✅ | | |
| Node ID 할당 | 1 | | |
| Thread 조인 확인 | ✅ | | |
| CASE 세션 | ✅ | | |

### 2-4. Attribute Read 비교

**chip-tool (oracle)**:
```bash
chip-tool booleanstate read state-value 1 1
# → FALSE
```

**matterjs-server (WebSocket)**:
```json
{
  "message_id": "2",
  "command": "read_attribute",
  "args": {
    "node_id": 1,
    "attribute_path": "1/69/0"
  }
}
```

(attribute_path: endpoint/cluster/attribute = 1/0x0045/0x0000)

| 비교 항목 | chip-tool | matterjs-server | 일치 |
|----------|-----------|-----------------|:----:|
| BooleanState value | FALSE | | |
| 응답 시간 | ~2s | | |

### 2-5. 이벤트 구독 (chip-tool에 없는 기능)

```json
{
  "message_id": "3",
  "command": "start_listening"
}
```

matterjs-server만의 기능 — 문 열림/닫힘 실시간 이벤트 수신.
chip-tool로는 불가능하므로 물리적으로 문을 열었다 닫으며 확인.

---

## Phase 3: fabric 이관 (chip-tool → matterjs-server)

chip-tool과 matterjs-server는 각자 fabric을 가진다.
동일 디바이스에 복수 fabric commissioning 가능 (Matter 스펙).

**전략 A**: matterjs-server로 새로 commissioning (별도 fabric)
**전략 B**: chip-tool fabric 데이터를 matterjs-server로 마이그레이션

→ 전략 A 우선 (더 단순). 검증 후 chip-tool은 디버깅 도구로만 유지.

---

## 트러블슈팅 기록

(검증 진행하며 추가)

---

## 참고

- [matterjs-server GitHub](https://github.com/matter-js/matterjs-server)
- [matter.js SDK](https://github.com/matter-js/matter.js) (v0.16.9-alpha.0-20260204)
- 소스 클론: `~/repos/3rd/matterjs-server`, `~/repos/3rd/matter.js`
- chip-tool 빌드/배포: [HOWTO.md](../HOWTO.md#8-matter-commissioning-chip-tool)
- Matter 아키텍처: [MQTT-HA.md](MQTT-HA.md)

> 로드맵은 [README.md](../README.md#로드맵) 참조.
