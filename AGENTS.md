# HomeAgent Config - 에이전트 지침

@README.md
@OFFICE.md (private)

---

# 현재 디바이스 확인

``` bash
cat .current-device-ip
```

## 프로젝트 관리

### 이슈 트래킹 (beads_rust)

```bash
# 기본
br list                          # 이슈 목록
br show <id>                     # 이슈 상세
br show <id> --json              # JSON 출력

# 생성
br create "제목"                 # 기본 생성
br create "제목" -p p0 -l "tag1,tag2" -t epic   # 우선순위+라벨+타입

# 상태 변경
br update <id> -s in_progress    # 상태: open, in_progress, blocked, deferred, closed
br update <id> -p p1             # 우선순위: p0~p4
br update <id> --title "새 제목"

# 닫기 — ⚠️ design/acceptance_criteria/notes 필드 NOT NULL 제약!
# 이전에 create만 한 이슈는 close 시 DB 에러 발생
# 해결: update로 필수 필드 채운 후 close
br update <id> \
  --design "설계 요약" \
  --acceptance-criteria "완료 조건" \
  --notes "작업 노트"
br close <id>                    # 이제 close 가능
br close <id> --force            # 의존성 무시하고 닫기

# 코멘트
br comments <id>                 # 코멘트 목록
br comments add <id> "코멘트 텍스트"          # 코멘트 추가
br comments add <id> --message "코멘트 텍스트" # --message 플래그도 가능
br comments add <id> -f comment.md            # 파일에서 읽기

# 동기화
br sync --flush-only             # JSONL 내보내기 (git commit 전 필수)

# 검사
br lint <id>                     # 누락 필드 확인
br list --status open            # 열린 이슈만
```

#### br 자주 하는 실수

| 실수 | 원인 | 해결 |
|------|------|------|
| `br close` → NOT NULL constraint | design/acceptance_criteria/notes 비어있음 | `br update`로 필수 필드 채운 후 close |
| `br comment <id> "text"` | comment**s** add 필요 | `br comments add <id> "text"` |
| `br update <id> -s done` | done은 유효하지 않음 | `br close <id>` 또는 `-s closed` |
| `br comment <id> -m "text"` | -m 옵션 없음 | `br comments add <id> --message "text"` |

### Jira (MAT 프로젝트)

**⚠️ Jira 이슈 상태 변경은 반드시 사용자 승인 후 진행.** 

## 에이전트 원칙

### 마음가짐

**"달에 보내는 임베디드 시스템"**

- 클라우드 없이 자립
- 프라이버시 보장
- 개인 에이전트와 협업 준비

### 핵심 규칙

1. **가설을 신뢰하지 마라** - 증거 첨부 필수
2. **추가보다 제거** - 복잡도는 버그의 온상
3. **자기 복구 가능한 상태머신** - 무한 대기/루프 금지

### npm-shrinkwrap 주의점 (Yocto 오프라인 빌드)

- `optionalDependencies`에 나열된 패키지도 shrinkwrap에 **resolve 엔트리**(resolved URL + integrity)가 있어야 설치됨. 없으면 Yocto가 건너뜀
- 코드가 `import "pkg"`로 하드 임포트하면 optional이 아닌 **사실상 필수**. shrinkwrap에서 `optionalDependencies` → `dependencies`로 이동할 것
- 네이티브 prebuild 바이너리(`prebuilds/linux-x64/` 등)는 `do_install`에서 타겟 외 아키텍처 제거 필수 (QA `arch` 에러)
- 상세: `docs/YOCTO-OFFLINE-FIRST.md`

### 인바리언트 (절대 금지)

**이 규칙을 어기면 작업 전체를 되돌려야 합니다. 이슈 단위 작업 시에도 반드시 확인하세요.**

#### 아키텍처

| 금지 | 허용 | 이유 |
|------|------|------|
| 프로토콜 엔진에서 상태 직접 변경 | Go 컨트롤러만 상태 관리 | 단방향 흐름 |
| 클라우드 의존 로직 | 온디바이스 우선 | Data Privacy |
| 허브에서 Python 사용 | Go + Node.js만 사용 | 런타임 단순화 |
| LLM 응답을 직접 실행 | `action`/`surface` 블록 파싱 후 실행 | 안전한 에이전트 |

#### A2UI 테마

| 금지 | 허용 | 이유 |
|------|------|------|
| UI 컴포넌트에 색상 리터럴 (`#hex`) | CSS 변수만 사용 (`var(--token)`) | 테마 일관성 |
| 컴포넌트 안에서 테마 결정 | 서버(Go)가 팔레트 JSON 전달 → 뷰어가 CSS 변수로 주입 | 단일 소스 |
| LLM surface에서 하드코딩 색상 | 팔레트 토큰만 사용 | A2UI 선언적 원칙 |
| 시간/상태 기반 테마 로직을 프론트에서 처리 | Go surface.go에서만 결정 | 서버 단일 결정권 |

> **테마 경로**: `Go surface.go (팔레트 결정)` → `GET /api/home (JSON)` → `app.ts applyTheme() (CSS변수 주입)` → `모든 컴포넌트 (변수 참조)`
>
> ✅ **위반 해소됨** (ff8d83e): 전체 UI 컴포넌트 `#hex` → `var(--ha-*)` 전환 완료. `styles.ts`에 25개 CSS 변수 중앙 정의. 새 컴포넌트 추가 시 반드시 CSS 변수로.

#### Matter / WS

| 금지 | 허용 | 이유 |
|------|------|------|
| 복수 goroutine에서 WS ReadJSON | 단일 ReadLoop만 읽기 | 경합 크래시 방지 |
| ReadLoop 시작 전에 WS 명령 전송 | ReadLoop goroutine 먼저 시작 | waitResponse 블록 방지 |
| matterjs-server WS 끊김 시 panic | 5초 후 자동 재연결 | 자기 복구 |

#### 배포

| 금지 | 허용 | 이유 |
|------|------|------|
| 수동 scp/ssh 배포 | `./run.sh ha-deploy` 사용 | 재현성 |
| 환경변수를 코드에 하드코딩 | `.env.rpi5` + `~/.env.local` | 비밀 분리 |
| `aliases.json` 없이 배포 | 항상 포함 | 디바이스 이름/방 매핑 필수 |

#### 에이전트 협력 (멀티세션)

| 금지 | 허용 | 이유 |
|------|------|------|
| TTS/Telegram/채팅봇 직접 구현 | OpenClaw 생태계에 위임 | 보안 + 생태계 전략 |
| br 이슈 범위 밖 코드 수정 | 이슈에 명시된 파일/기능만 수정 | 병렬 작업 충돌 방지 |
| 인바리언트 위반 "임시" 코드 | 없음. 인바리언트는 예외 없음 | 되돌리기 비용 > 처음부터 준수 |

---

## 프로젝트 현황 (2026-03-12)

### 동작 중인 스택

```
Flutter App (Android APK / ivi-homescreen)
  └── WebView ──▶ Go HomeAgent v0.8 (:8080)
                   ├── REST API: /api/devices, /api/devices/:id, /api/devices/command (8 cmds)
                   │             /api/commission, /api/chat, /api/home, /api/events(SSE)
                   ├── LLM: OpenRouter (Gemini 2.5 Flash) — 자연어→디바이스 제어
                   ├── A2UI: 시간 기반 Home Surface + LLM 동적 surfaceUpdate
                   ├── Matter WS (단일 ReadLoop) → matterjs-server (:5580)
                   ├── BLE relay: Flutter ↔ matterjs WS (:5581) — Android BLE 중계
                   ├── OTBR: ot-br-posix NDK arm64 — Thread Border Router
                   └── Lit UI: 대시보드, 디바이스 카드, 채팅 패널, A2UI 렌더러
```

### 크로스플랫폼 빌드 상태

| 타겟 | 빌드 | 상태 |
|------|------|------|
| Flutter Linux Desktop | `./run.sh flutter-build` | ✅ 동작 |
| Flutter Android APK | `./run.sh apk-build` | ✅ 46MB (targetSdk=35, Android 15) |
| Go Android arm64 | `./run.sh apk-go` | ✅ 7.2MB |
| OTBR NDK arm64 | `./run.sh otbr-build` | ✅ otbr-agent 6.9MB + ot-ctl 12KB |
| Yocto flutter-engine | `bitbake flutter-engine` | ✅ 빌드 성공 |
| Yocto 전체 이미지 | `bitbake homeagent-app` | 🔲 ivi-homescreen 빌드 미완 |

### REST API 명령 (8개)

`POST /api/devices/command` — `on`, `off`, `set_level`, `set_color`, `set_color_temp`, `set_thermostat`, `lock`, `unlock`

상세: [docs/API.md](docs/API.md)

### 디바이스 (aliases.json)
- Node 1: 현관문 센서 (현관, contact_sensor, Thread)
- Node 7: 화장실 센서 (화장실, contact_sensor, Thread)
- Node 8: 거실 플러그 (거실, on_off_plug, WiFi)

### 배포 / 개발 명령

```bash
# RPi5 배포 (Yocto 기준)
./run.sh ha-deploy          # 전체 빌드+배포+시작 (원커맨드)
./run.sh ha-status / ha-logs

# Android 보드 배포 (범용 — RK3576/RK3588/etc.)
./run.sh android deploy     # 전체 빌드+배포+시작
./run.sh android start      # 서비스만 (재)시작
./run.sh android stop       # 서비스 종료
./run.sh android status     # 상태 확인
./run.sh android logs [t]   # 로그 (matter/go/otbr/all)
./run.sh android thread-start   # OTBR + Thread 네트워크
./run.sh android thread-status  # Thread 상태

# Flutter 개발
./run.sh flutter-run         # Linux desktop hot reload
./run.sh flutter-server      # Go 서버 로컬 (Matter 없이)

# 개별 빌드
./run.sh apk-build           # 릴리즈 APK
./run.sh apk-go              # Go arm64 크로스컴파일
./run.sh otbr-build          # OTBR NDK arm64 빌드

# Yocto
./run.sh shell               # FHS 빌드 환경 진입
./run.sh bb-cmd <recipe>     # bitbake 실행

# 번들
./run.sh bundle              # Go+Node.js+matterjs arm64 번들
```

### 주요 파일

| 경로 | 역할 |
|------|------|
| `go/internal/hub/hub.go` | 중앙 코디네이터 (상태, SSE, REST 8 commands, 에이전트) |
| `go/internal/hub/surface.go` | 시간 기반 A2UI Home Surface 생성 |
| `go/internal/agent/agent.go` | LLM 에이전트 (Chat + ReactToEvent) |
| `go/internal/matter/client.go` | matterjs-server WS 클라이언트 (단일 ReadLoop) |
| `go/internal/config/config.go` | 환경변수 설정 |
| `go/internal/a2a/executor.go` | A2A 에이전트 실행기 (HomeAgentExecutor) |
| `flutter/lib/main.dart` | 플랫폼 감지 → ShellNative / ShellWebView |
| `flutter/lib/shell_webview.dart` | Android/Yocto WebView 셸 |
| `flutter/lib/shell_native.dart` | Linux desktop Flutter 위젯 |
| `flutter/lib/ble_relay.dart` | BLE 바이트 중계 (Flutter ↔ matterjs WS) |
| `flutter/lib/ble_commissioning.dart` | BLE 커미셔닝 UI (Plan B) |
| `ui/src/app.ts` | Lit 대시보드 (SSE, 테마, A2UI) |
| `scripts/android-deploy.sh` | Android 보드 배포/실행/Thread 관리 |
| `scripts/build-otbr.sh` | OTBR NDK arm64 재현 빌드 |
| `aliases.json` | 디바이스 별칭/방 매핑 |
| `flake.nix` | Yocto FHS + dev shell (Android SDK 포함) |

### 현재 벽: Android BLE 커미셔닝 (bd-3cw)

**RPi5에서는 matterjs로 BLE 커미셔닝 성공. Android에서만 실패.**

근본 원인 발견 (2026-03-12):
- **FlutterBluePlus `setNotifyValue(true)` → notify(0x0001) 우선 선택**
- Matter BTP C2는 indicate(0x0002) 전용
- CCCD 0x0001 → 디바이스가 indication 미전송 → BTP handshake timeout
- **수정 완료**: `forceIndications: true` (커밋 a860b5c)
- **보드 검증 대기**

BLE relay 흐름 + WS 프로토콜 스키마: `office/ws-protocol-schema.md` (git 미추적)

### BLE relay 아키텍처 (Android BLE 커미셔닝)

```
Flutter APK                    matterjs-server
(flutter_blue_plus)            (Matter 프로토콜)
     │                              │
     │◀── WS :5581 ──────────────▶│
     │     ble_scan_start/stop      │
     │     ble_connect/disconnect   │
     │     ble_write (C1 바이트)    │
     │     ble_data (C2 바이트)     │
     │                              │
     │   Flutter = BLE 바이트 셔틀  │
     │   matterjs = 프로토콜 전체   │
     │   (BTP/PASE/WiFi/CASE)       │
```

noble(Linux HCI)은 Android에서 동작 불가 → Flutter BLE가 대신 BLE 물리 계층 담당.
프로토콜 로직은 matterjs-server가 전부 처리. Flutter는 바이트를 중계만 함.

---

## ⚠️ 헷갈리기 쉬운 것

### Node.js 버전: devShell ≠ Yocto 타겟

- `flake.nix` devShell: **Node 22** (로컬 개발용)
- Yocto 이미지 (RPi5): **Node 20.18.2** (타겟 런타임)
- **달라도 문제없다.** devShell은 개발 편의, Yocto는 자체 도구체인으로 빌드. 서로 독립.
- 상세: `VERSION.md`

### NixOS Yocto 빌드: glibc.dev 필수

- `flake.nix` FHS 환경에 `glibc.dev` + `linuxHeaders` 필수
- flutter-engine 번들 clang이 `/usr/include` C 헤더를 기대
- NixOS에는 `/usr/include` 없음 → `buildFHSEnv` `targetPkgs`에 추가해야 동작
- 상세: [docs/FLUTTER.md](docs/FLUTTER.md) > "NixOS 호스트 빌드" 섹션

### Android SDK: --impure 필요

- `nix develop .#dev --impure` — Android SDK가 unfree 패키지
- `flake.nix`에 `allowUnfree = true` 설정됨
- `./run.sh apk-build`가 자동으로 `--impure` 전달

---

## 문서

| 문서 | 내용 |
|------|------|
| [docs/API.md](docs/API.md) | REST API 명세 (8 commands, SSE, OHF 호환) |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter 셸 아키텍처 + NixOS 빌드 가이드 |
| [docs/A2UI.md](docs/A2UI.md) | 에이전트 주도 동적 UI 전략 |
| [docs/A2A.md](docs/A2A.md) | 에이전트 프로토콜, Constitutional AI |
| [docs/THREAD.md](docs/THREAD.md) | OTBR NDK 빌드 가이드 + 7개 CMake 이슈 해결 |
| [docs/INSTALL.md](docs/INSTALL.md) | Android 보드 설치 가이드 (원커맨드 배포) |
| [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) | RPi5 vs Android 전체 스택 비교 |
| [VERSION.md](VERSION.md) | Yocto/RPi5/Flutter 버전 매트릭스 |

## Landing the Plane (세션 종료)

```bash
git pull --rebase
br sync --flush-only
git add -A && git commit -m "작업 내용"
git push
git status  # "up to date with origin" 확인
```

**작업은 `git push` 성공 전까지 미완료**
