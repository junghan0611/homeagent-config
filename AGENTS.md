# HomeAgent Config - 에이전트 지침

@README.md
@OFFICE.md (private)

## How to Read This

If you see "Hailo-8 NPU 398 FPS" or "sLLM 100% accuracy" in our docs, pause. Those are off-the-shelf components — a Hailo Model Zoo model and a 43-second LoRA fine-tune on 52 samples. Anyone can reproduce them in an afternoon. They are not the point.

**What you're looking at is a wiring project.** One repo that connects Yocto, Go, Flutter, Matter, Thread (OTBR), NPU (Hailo-8), sLLM (Qwen3-0.6B), and A2A protocol into a single reproducible image. Each piece exists individually in the open. What doesn't exist elsewhere is the integration — the `bitbake` that builds it all, the `./run.sh ha-deploy` that ships it, the Go server that ties Matter WebSocket to REST to SSE to Flutter to sLLM fallback chain.

The ugly parts are the real work: kernel 4K page size patches for Hailo driver compatibility. Firmware version conflicts between meta-raspberrypi and meta-hailo. npm-shrinkwrap offline resolution for Yocto hermeticity. Cross-compiling llama.cpp with NDK r27 for Android and native ARM for Yocto — same GGUF, same HTTP API, same Go code, zero platform branches. GStreamer pipeline plumbing from camera to NPU to Matter occupancy event.

**No single component here is novel.** The claim is: `git clone` this repo, run `bitbake`, flash the image, and you get a working smart home hub with Matter + NPU + sLLM + Flutter UI on RPi5 — or the same stack on RK3576/RK3588S with a different `MACHINE=` flag. That's it. End-to-end reproducibility across boards. Everything else is commodity.

If you're an agent writing docs for this project, read the `No Hype` section below. Don't inflate components. Describe integration.

---

## Android python-matter-server (deprecated)

`deprecated/android-docker/` 이동됨. 경동 프로젝트 요청으로 임시 Docker 포장했던 것.
Android 지원은 Flutter APK로 충분. python-matter-server Docker는 핵심 가치 아님.

scripts/ 폴더는 matterjs-server(오픈소스) 전용.

## Phase 로드맵 (흔들리지 않는 방향)

| Phase | 이름 | 핵심 | 상태 |
|-------|------|------|------|
| 1 | Yocto + Protocol | RPi5에서 Matter 동작 증명 | ✅ |
| 2 | Matter + Go Controller | 동작하는 스마트홈 허브 (v0.8) | ✅ |
| 3 | Cross-platform | 같은 코드, 다른 하드웨어 (RPi5 + RK3576 + OPi5) | ✅ |
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

### 현재 상태 (2026-04-03 업데이트)

- Go: 18 REST 엔드포인트, 117 PASS
- Flutter: 89 PASS, 디바이스 상세 화면 완성
- WS 커버리지: 13/31 (42%)
- RPi5 + Android 양쪽 배포 동작
- **OPi5는 lab target**: 커널 6.14 + Mesa 24.1.7 + Mali-G610 + HDMI 4K 검증 완료. vendor 6.1/RKNN NPU 경로는 보류 — 필요 시 llmlog `20260331T114944` 참고.
- 에이전트4 리서치: HA 생태계 5개 분석 완료 (office/research-*.md)

---

# 디바이스 접속

## IP 확인

```bash
cat .current-device-ip        # RPi5 (기본)
cat .current-device-ip.opi5   # OPi5
```

## SSH 접속

```bash
./run.sh ssh              # RPi5 (기본, .current-device-ip 사용)
./run.sh ssh opi5         # OPi5 (192.168.0.177)
./run.sh ssh opi5 "uname -a"  # OPi5에서 원격 명령 실행
```

- SSH 키: `.sshkey/id_ed25519` (양쪽 공유)
- 패스워드: `homeagent` (키 미등록 시)
- 키 등록: `./run.sh setup-key opi5`

## 디바이스 현황 (2026-04-03 업데이트)

| | RPi5 | OPi5 |
|---|---|---|
| **SoC** | BCM2712 (4×A76) | RK3588S (4×A76 + 4×A55) |
| **RAM** | 8GB | 4GB |
| **NPU** | Hailo-8 (26 TOPS, 외장) | RKNN (6 TOPS, 내장) — 미검증 |
| **Kernel** | 6.6 LTS (linux-raspberrypi) | **6.14** (linux-yocto-dev) |
| **Mesa** | 24.0.7 (vc4/v3d) | **24.1.7** (panfrost + panthor kmod) |
| **GPU** | VideoCore VII | **Mali-G610 (panthor 1.3.0)** ✅ |
| **Display** | HDMI (vc4-kms-v3d) | **HDMI 4K@30Hz (dw-hdmi-qp)** ✅ |
| **USB-C DP** | — | PHY 로드됨, DRM 미머지 (6.14) |
| **전원** | 5V/5A USB-C | **USB-C to C 필수** (4K 시) |
| **이미지** | 풀 스택 (Docker+Go+matterjs+OTBR) | core-image-minimal + GPU |
| **IP** | `.current-device-ip` | 192.168.0.177 |
| **NIC** | eth0 | end0 |

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

### No Hype — Honest Writing Principle

**The value of this project is reproducible end-to-end integration, not any single component.**

Every piece — Yocto, Go, Flutter, Matter, sLLM, NPU, A2A — exists individually in the open.
What doesn't exist elsewhere is **one repo that wires them all together into a reproducible platform**.
That's the only thing worth claiming.

**Rules for agents writing docs, botlog, llmlog:**

| Don't | Do | Why |
|-------|-----|-----|
| "We achieved 100% accuracy with LoRA fine-tuning" | "Off-the-shelf Qwen3-0.6B + 43s LoRA. The point is it runs on-device without cloud" | 52 samples / 43s is not ML research. Don't frame it as one |
| "YOLOv8s 398 FPS benchmark on Hailo-8" as a headline | "Hailo Model Zoo model runs on our Yocto image. The work was kernel/driver integration" | We didn't train the model. We built the platform that runs it |
| Framing a single component as the achievement | Frame the **integration** as the achievement | Individual parts are commodity. The wiring is the craft |
| "First to do X" / "Novel approach" | State facts. Let the reader judge | We're engineers, not paper authors |

**Litmus test before writing**: *"Can someone find this component on GitHub in 5 minutes?"*
- Yes → it's commodity. Describe what we did to **integrate** it, not the component itself.
- No → then it might be genuinely ours. Describe it honestly.

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

먼저 [docs/README.md](docs/README.md)를 읽어라. 이 파일이 문서 지도다. 어떤 문서가 SSOT인지, 어떤 문서가 근거 로그인지, 어떤 문서를 어디로 흡수할지 명시한다.

### 에이전트 기본 읽기 순서

| 상황 | 먼저 읽을 문서 |
|------|----------------|
| 처음 리포 파악 | [README.md](README.md) → [docs/README.md](docs/README.md) → [VERSION.md](VERSION.md) |
| 코드 수정 | [AGENTS.md](AGENTS.md) → [INVARIANTS.md](INVARIANTS.md) → 관련 docs |
| 빌드/플래시 | [HOWTO.md](HOWTO.md) → [docs/BUILD.md](docs/BUILD.md) → [VERSION.md](VERSION.md) |
| 하드웨어/SSH/동글 | [HARDWARE.md](HARDWARE.md) |
| API/클라이언트 | [docs/API.md](docs/API.md) + `go/internal/hub/hub.go` 라우트 확인 |
| 플랫폼 분기 | [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) |
| Yocto 레시피 | [docs/YOCTO-OFFLINE-FIRST.md](docs/YOCTO-OFFLINE-FIRST.md) |
| Zigbee/MQTT/ESP32 경계 | [docs/EDGE-ZIGBEE.md](docs/EDGE-ZIGBEE.md) + `~/repos/gh/edgeagent-config` |

### 핵심 docs

| 문서 | 역할 |
|------|------|
| [docs/README.md](docs/README.md) | 문서 지도 — 역할, 읽는 시점, 흡수/이동 방향 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | ADR — 구조 결정 근거 |
| [docs/API.md](docs/API.md) | REST/SSE API 명세. 수동 엔드포인트 수는 stale 주의 |
| [docs/MATTER.md](docs/MATTER.md) | Matter SDK/backend 전략 |
| [docs/BUILD.md](docs/BUILD.md) | 빌드 환경, 산출물, 빌드팜 워크플로 |
| [docs/THREAD.md](docs/THREAD.md) | OTBR/RCP/Thread 가이드 |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter 셸 아키텍처 + NixOS 빌드 |
| [docs/A2UI.md](docs/A2UI.md) | 에이전트 주도 동적 UI 전략 |
| [docs/A2A.md](docs/A2A.md) | 에이전트 프로토콜, Constitutional AI |
| [docs/YOCTO-OFFLINE-FIRST.md](docs/YOCTO-OFFLINE-FIRST.md) | Yocto 오프라인 레시피 정책 |
| [docs/EDGE-ZIGBEE.md](docs/EDGE-ZIGBEE.md) | HomeAgent ↔ Edge/Zigbee/MQTT 경계 |
| [VERSION.md](VERSION.md) | 버전/스택 SSOT |
| [HARDWARE.md](HARDWARE.md) | 실제 장비 상태 SSOT |

## Landing the Plane (세션 종료)

```bash
git pull --rebase
br sync --flush-only
git add -A && git commit -m "작업 내용"
git push
git status  # "up to date with origin" 확인
```

**작업은 `git push` 성공 전까지 미완료**
