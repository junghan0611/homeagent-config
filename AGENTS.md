# HomeAgent Config - 에이전트 지침

@README.md
@OFFICE.md (private)

---

## Android python-matter-server 이용 시
android-docker/README.md 참조. Docker(python-matter-server) + Native(OTBR BBR=ON) 하이브리드.
CHIP SDK AAR로 BLE 커미셔닝 후 python-matter-server에 multi-admin handoff.

matterjs-server와 python-matter-server는 별개. 섞지 마라.
scripts/ 폴더는 matterjs-server(오픈소스) 전용.

## Phase 로드맵 (흔들리지 않는 방향)

| Phase | 이름 | 핵심 | 상태 |
|-------|------|------|------|
| 1 | Yocto + Protocol | RPi5에서 Matter 동작 증명 | ✅ |
| 2 | Matter + Go Controller | 동작하는 스마트홈 허브 (v0.8) | ✅ |
| 3 | Cross-platform | 같은 코드, 다른 하드웨어 (RPi5 + RK3576) | ✅ |
| **4** | **HA Ecosystem + Flutter-first** | **matterjs-server 위임, Go 확장, Flutter 유니버셜 클라이언트** | **← current** |
| 5 | Agent Intelligence | sLLM, A2UI, A2A, EdgeAI | |
| 6 | Production + Scale | 양산, RK3588, Hailo NPU | |

### Phase 4 원칙

1. **Docker = Matter+OTBR 배포** — python-matter-server + OTBR Docker 컨테이너. 네이티브 실행 (chroot 폐기)
2. **Go 서버 = 확장 레이어** — 커스텀 REST, aliases, sLLM, A2UI, 클라이언트별 API
3. **Flutter = 유니버셜 클라이언트, 네이티브 UI 기본** — Android는 반드시 네이티브 UI (NavShell). WebView는 RPi5 전용. Android 종속 금지
4. **HA Kotlin→Dart** — ha-android 핵심 로직을 Flutter로 포팅, 오픈소스 기여 경로

### Flutter UI 규칙 (흔들리지 않음)

| 플랫폼 | UI 모드 | 이유 |
|--------|---------|------|
| **Android** | `NavShell` (네이티브) | WebView 품질 떨어짐. 기본값 `NATIVE_UI=true` |
| **Linux Desktop** | `NavShell` (네이티브) | 개발용 hot reload |
| **Yocto RPi5** | `ShellWebView` | ivi-homescreen Wayland, Lit UI |

> WebView APK는 쓰지 않는다. `NATIVE_UI` 기본값은 `true`.

### 아키텍처 결정 (2026-03-25 업데이트)

```
APP → Go Server (:8080) → python-matter-server (:5580) → OTBR → Matter 디바이스
                            ↑ Docker container              ↑ Docker container
```

- **앱은 Go 서버만 안다** (단일 진입점, 이중 경로 금지)
- **Go가 matterjs WS를 래핑** (13/31 명령, 42% 커버리지)
- **Go가 확장 API 추가** (aliases, LLM, A2UI, OTBR, SSE)
- **matter_client.dart는 예비용** (경량 모드/디버깅, 현재 미사용)

### 현재 상태 (2026-03-20)

- Go: 18 REST 엔드포인트, 117 PASS
- Flutter: 89 PASS, 디바이스 상세 화면 완성
- WS 커버리지: 13/31 (42%)
- RPi5 + Android 양쪽 배포 동작
- 에이전트4 리서치: HA 생태계 5개 분석 완료 (office/research-*.md)

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
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | ADR 5개 — Go, Flutter, matterjs, 프로세스 분리, 부팅 복원 |
| [docs/MATTER.md](docs/MATTER.md) | Matter SDK 전략, 런타임 실측(65MB), matter.js 로드맵 |
| [docs/BUILD.md](docs/BUILD.md) | 빌드 환경, 리소스, 개발 머신 + 빌드 팜 분업 |
| [docs/GO-MATTERJS-OVERLAP.md](docs/GO-MATTERJS-OVERLAP.md) | Go↔matterjs 중복 분석 — 프록시+확장 유지 판단 |
| [docs/API.md](docs/API.md) | REST API 명세 (18 엔드포인트, SSE, OHF 호환) |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter 셸 아키텍처 + NixOS 빌드 가이드 |
| [docs/A2UI.md](docs/A2UI.md) | 에이전트 주도 동적 UI 전략 |
| [docs/A2A.md](docs/A2A.md) | 에이전트 프로토콜, Constitutional AI |
| [docs/THREAD.md](docs/THREAD.md) | OTBR NDK 빌드 가이드 + 7개 CMake 이슈 해결 |
| [docs/INSTALL.md](docs/INSTALL.md) | Android 보드 설치 가이드 (원커맨드 배포) |
| [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) | RPi5 vs Android 전체 스택 비교 |
| [VERSION.md](VERSION.md) | Yocto/RPi5/Flutter/matter-server 버전 매트릭스 |

## Landing the Plane (세션 종료)

```bash
git pull --rebase
br sync --flush-only
git add -A && git commit -m "작업 내용"
git push
git status  # "up to date with origin" 확인
```

**작업은 `git push` 성공 전까지 미완료**
