# HomeAgent Config - 에이전트 지침

@README.md

---

## 프로젝트 관리

### 이슈 트래킹 (beads_rust)

```bash
br list              # 이슈 목록
br show <issue-id>   # 이슈 상세
br create "제목"     # 이슈 생성
br update <id> -s in_progress  # 상태 변경
br close <id>        # 완료
br sync --flush-only # JSONL 동기화
```

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
> ⚠️ **현재 위반 상태** (ha-2y3): app.ts/a2ui-renderer.ts에 하드코딩 색상 잔존. 새 컴포넌트 추가 시 반드시 CSS 변수로.

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

## 프로젝트 현황 (2026-03-06)

### 동작 중인 스택

```
Flutter App (ivi-homescreen / Android APK)
  └── WebView ──▶ Go HomeAgent v0.8 (:8080)
                   ├── REST API: /api/devices, /api/devices/:id, /api/devices/command (8 cmds)
                   │             /api/commission, /api/chat, /api/home, /api/events(SSE)
                   ├── LLM: OpenRouter (Gemini 2.5 Flash) — 자연어→디바이스 제어
                   ├── A2UI: 시간 기반 Home Surface + LLM 동적 surfaceUpdate
                   ├── Matter WS (단일 ReadLoop) → matterjs-server (:5580)
                   └── Lit UI: 대시보드, 디바이스 카드, 채팅 패널, A2UI 렌더러
```

### 크로스플랫폼 빌드 상태

| 타겟 | 빌드 | 상태 |
|------|------|------|
| Flutter Linux Desktop | `./run.sh flutter-build` | ✅ 동작 |
| Flutter Android APK | `./run.sh apk-build` | ✅ 43.7MB (targetSdk=35, Android 15) |
| Go Android arm64 | `./run.sh apk-go` | ✅ 7.2MB |
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
# RPi5 배포
./run.sh ha-deploy          # 전체 빌드+배포+시작 (원커맨드)
./run.sh ha-status / ha-logs

# Flutter 개발
./run.sh flutter-run         # Linux desktop hot reload
./run.sh flutter-server      # Go 서버 로컬 (Matter 없이)

# Android APK
./run.sh apk-build           # 릴리즈 APK
./run.sh apk-go              # Go arm64 크로스컴파일

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
| `flutter/lib/main.dart` | 플랫폼 감지 → ShellNative / ShellWebView |
| `flutter/lib/shell_webview.dart` | Android/Yocto WebView 셸 |
| `flutter/lib/shell_native.dart` | Linux desktop Flutter 위젯 |
| `ui/src/app.ts` | Lit 대시보드 (SSE, 테마, A2UI) |
| `aliases.json` | 디바이스 별칭/방 매핑 |
| `flake.nix` | Yocto FHS + dev shell (Android SDK 포함) |

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

## 관련 프로젝트

| 프로젝트 | 위치 | 활용 |
|----------|------|------|
| kyungdong-rockchip | `/home/junghan/repos/work/kyungdong-rockchip/` | Matter/Thread 참고 |

## 문서

| 문서 | 내용 |
|------|------|
| [docs/API.md](docs/API.md) | REST API 명세 (8 commands, SSE, OHF 호환) |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter 셸 아키텍처 + NixOS 빌드 가이드 |
| [docs/A2UI.md](docs/A2UI.md) | 에이전트 주도 동적 UI 전략 |
| [docs/A2A.md](docs/A2A.md) | 에이전트 프로토콜, Constitutional AI |
| [VERSION.md](VERSION.md) | Yocto/RPi5/Flutter 버전 매트릭스 |

---

## Landing the Plane (세션 종료)

```bash
git pull --rebase
br sync --flush-only
git add -A && git commit -m "작업 내용"
git push
git status  # "up to date with origin" 확인
```

**작업은 `git push` 성공 전까지 미완료**
