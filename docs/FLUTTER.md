# Flutter Shell — 크로스플랫폼 배포 계층

> **Scope: origin lane.** Flutter/Android는 high-spec origin lane 클라이언트 실험이다.
> 활성 메인 레인(SG2000 RISC-V Linux + Zig + C906L)은 [`../runtime/README.md`](../runtime/README.md) 참고.
> 본문의 `ha-ldi.1` 등 beads 흔적은 origin-lane 이력 보존용이다.

Flutter는 HomeAgent의 **배포 셸(delivery shell)**이다.
UI 로직은 서버(Go)가 결정하고([A2UI](A2UI.md)), Flutter는 그 결과물을 WebView 또는 네이티브 위젯으로 보여줄 뿐이다.

## 아키텍처

```
┌─────────────────────────────────────────────┐
│  Flutter App                                │
│  ├── Android → ShellWebView (WebView)       │  APK 배포
│  ├── Yocto   → ShellWebView (ivi-homescreen)│  RPi5 이미지
│  └── Linux   → ShellNative  (Flutter 위젯)  │  개발 전용
│               ↕                             │
│       Go HomeAgent (:8080)                  │  REST API + SSE
│       matterjs-server (:5580)               │  Matter 디바이스
└─────────────────────────────────────────────┘
```

| 플랫폼 | 셸 | 용도 |
|--------|-----|------|
| **Android** | `ShellWebView` | 클라이언트 APK 배포 (월패드 등) |
| **Yocto/Weston** | `ShellWebView` via ivi-homescreen | RPi5 프로덕션 이미지 |
| **Linux Desktop** | `ShellNative` | 개발/디버깅 (Go API 직접 호출) |

### 핵심 원칙

- **Flutter는 UI 로직을 갖지 않는다** — A2UI 패러다임에 따라 서버가 surfaceUpdate JSON을 보내면 렌더링만 함
- **WebView가 기본** — Lit 프론트엔드 + A2UI 렌더러가 이미 동작. Flutter는 WebView 컨테이너
- **ShellNative는 개발 편의** — Linux에서 WebView 없이 Go REST API를 직접 호출하는 Flutter 위젯. 프로덕션용 아님

---

## 빌드 환경

### 로컬 개발 (Flutter Linux Desktop)

```bash
nix develop .#dev          # Flutter 3.38.9 + Dart 3.10.8
./run.sh flutter-run       # Linux desktop 실행
./run.sh flutter-build     # 릴리즈 빌드
./run.sh flutter-analyze   # 정적 분석
```

### Yocto 크로스 빌드 (RPi5 arm64)

```bash
nix develop                # FHS 환경 진입 (Yocto 빌드용)
./run.sh bb-cmd homeagent-app  # bitbake: flutter-engine → ivi-homescreen → homeagent-app
```

#### Yocto 레이어 스택

| 레이어 | 역할 | 브랜치 |
|--------|------|--------|
| meta-flutter | flutter-engine, ivi-homescreen, flutter-sdk | scarthgap |
| meta-clang | clang 18.1.8 (flutter-engine 빌드 도구체인) | scarthgap |
| meta-homeagent | homeagent-app 레시피, 번들, 서비스 | main |

#### 빌드 체인

```
flutter-engine (Fuchsia clang 21.0 번들)
  → libflutter_engine.so (arm64)
  → flutter_tester (x64, 호스트)
      ↓
ivi-homescreen (Wayland compositor shell)
  → homescreen 바이너리
      ↓
homeagent-app (Flutter AOT bundle + backend bundle)
  → /opt/homeagent/ 에 설치
```

---

## NixOS 호스트 빌드 — `/usr/include` 문제와 해결

> **이 섹션은 NixOS에서 Yocto를 돌릴 때만 해당. Ubuntu/Debian에서는 해당 없음.**

### 문제

flutter-engine은 **자체 번들 clang(Fuchsia clang 21.0)**으로 호스트 도구(`clang_x64/`)를 빌드한다.
이 clang은 C 표준 헤더를 `/usr/include`에서 찾는다 — 모든 일반 Linux 배포판의 기본 경로.

**NixOS에는 `/usr/include`가 없다.**

Yocto 빌드는 `buildFHSEnv`(FHS 호환 샌드박스) 안에서 실행되지만,
기본 설정에서는 glibc 개발 헤더가 FHS 환경에 포함되지 않는다.

결과: flutter-engine 호스트 빌드에서 libcxx가 C 타입을 찾지 못함:

```
flutter/third_party/libcxx/include/__chrono/system_clock.h:35:
  error: reference to unresolved using declaration
  → using ::time_t (from <ctime>) 찾지 못함

flutter/third_party/libcxx/include/__thread/support/pthread.h:18:
  fatal error: 'pthread.h' file not found

flutter/third_party/libcxx/include/string.h:98:
  error: unknown type name 'size_t'
```

### 해결

`flake.nix`의 `buildFHSEnv` `targetPkgs`에 glibc 개발 헤더를 추가:

```nix
targetPkgs = pkgs: with pkgs; [
  # ... 기존 패키지 ...

  # FHS /usr/include C 헤더 — flutter-engine 번들 clang 호스트 빌드에 필요
  # buildFHSEnv는 glibc 라이브러리는 자동 포함하지만 dev 헤더는 빠짐
  # glibc.dev → /usr/include/{pthread.h,stdio.h,time.h,...}
  glibc.dev linuxHeaders
];
```

이것이 **표준 해결법**인 이유:

1. `buildFHSEnv`의 설계 의도 = "FHS 표준 경로를 만들어주는 것"
2. 모든 일반 Linux에 `/usr/include`가 있음 → NixOS FHS에도 있어야 정상
3. flutter-engine 번들 clang이 `/usr/include`를 기대하는 것은 정당한 가정
4. [NixOS/nixpkgs #10184](https://github.com/NixOS/nixpkgs/issues/10184) (2015)에서 동일 문제 보고됨

### 시도했으나 무효했던 방법

| 방법 | 결과 | 이유 |
|------|------|------|
| `CXXFLAGS:remove = "-stdlib=libc++"` bbappend | ❌ 무효 | GN 빌드는 Yocto CXXFLAGS를 참조하지 않음 |
| `extraOutputsToInstall = ["dev"]` | ❌ 무효 | glibc.dev에는 적용되지 않음 |
| do_compile:prepend에서 심링크 | ❌ 불완전 | GN은 do_configure에서 이미 경로 확정 |

### 관련 이슈

- [NixOS/nixpkgs #10184](https://github.com/NixOS/nixpkgs/issues/10184) — buildFHSEnv + Yocto, `/usr/include` 부재
- [flutter/flutter #170391](https://github.com/flutter/flutter/issues/170391) — meta-flutter CI에서 clang_x64 빌드 실패 (동일 구조)
- `ha-ldi.1` (beads) — 이 이슈의 로컬 트래킹

### 버전 매트릭스

| 구성요소 | 버전 | 비고 |
|----------|------|------|
| flutter-engine 번들 clang | Fuchsia clang **21.0.0**git | 호스트(x64) + 타겟(arm64) 빌드 |
| meta-clang | **18.1.8** | Yocto sysroot libc++ 제공 |
| NixOS glibc.dev | **2.42-47** | FHS `/usr/include` C 헤더 |
| linuxHeaders | **6.16.7** | FHS `/usr/include/linux/` 커널 헤더 |

---

## 파일 구조

```
flutter/
├── lib/
│   ├── main.dart              # 플랫폼 감지 → ShellNative / ShellWebView
│   ├── shell_native.dart      # Linux: Flutter 위젯 (Go REST 직접 호출)
│   ├── shell_webview.dart     # Android/Yocto: WebView 컨테이너
│   └── backend_process.dart   # Go + Node.js 프로세스 관리
├── android/                   # Android APK 설정
├── linux/                     # Linux desktop (GTK3)
└── pubspec.yaml               # webview_flutter 4.13.1
```

---

## Backend Bundle (RPi5 / Android)

Go + Node.js + matterjs-server를 단일 디렉토리로 번들:

```bash
./scripts/bundle-backend.sh    # → dist/homeagent-bundle-arm64/ (335MB)
```

| 구성요소 | 크기 | 내용 |
|----------|------|------|
| Go binary | 6.5 MB | `homeagent` 정적 바이너리 (arm64) |
| UI assets | 64 KB | Lit 프론트엔드 |
| Node.js | 93 MB | v20.18.2 linux-arm64 |
| matterjs-server | 237 MB | npm install 결과 |

---

## 로드맵

- [x] Flutter Linux Desktop 빌드 + 실행 확인
- [x] Backend bundle 스크립트
- [x] Yocto flutter-engine 빌드 (NixOS FHS 해결)
- [ ] Yocto ivi-homescreen + homeagent-app 전체 이미지
- [ ] RPi5 Weston 위에서 Flutter 앱 실행 검증
- [ ] Android APK 빌드 + Go arm64 번들 탑재
- [ ] 번들 크기 최적화 (matterjs 237MB → tree-shaking)

---

## 참고

- [A2UI](A2UI.md) — 서버 주도 UI 패러다임
- [API](API.md) — REST API 명세
- [YOCTO-OFFLINE-FIRST](YOCTO-OFFLINE-FIRST.md) — Yocto 오프라인 빌드 가이드
