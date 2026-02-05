# YOCTO OFFLINE-FIRST RECIPE POLICY

> 이 프로젝트는 **오프라인 빌드 우선(Offline-First)** 원칙을 따릅니다.
> 모든 Yocto/BitBake 레시피는 네트워크 없이 재현 가능해야 합니다.

## 왜 Offline-First인가?

### 임베디드 제품의 현실

```
1. 재현성 (Reproducibility)
   - 6개월 후 동일한 펌웨어를 다시 빌드할 수 있어야 함
   - "npm registry가 바뀌었어요"는 변명이 될 수 없음

2. 법적 컴플라이언스 (License Compliance)
   - 제품 출시 시 모든 오픈소스 라이센스 공개 필수
   - 600개 의존성? 모두 추적해야 함

3. 보안 감사 (Security Audit)
   - "어떤 버전을 사용하고 있나요?"
   - 모든 의존성이 명시적으로 기록되어야 함

4. 폐쇄망 환경 (Air-Gapped Build)
   - 공장, 보안시설 = 인터넷 없음
   - sstate-cache로 완전 오프라인 빌드 가능해야 함
```

## 레시피 유형별 정책

### 1. NPM 기반 패키지 (Node.js)

**금지 - 런타임 네트워크 의존**

```bitbake
# ❌ 절대 금지: 빌드 시 네트워크 접속
do_compile() {
    npm ci --production
}
```

**필수 - npmsw fetcher 사용**

```bitbake
# ✅ 올바른 방식: shrinkwrap으로 의존성 고정
inherit npm

SRC_URI = " \
    npm://registry.npmjs.org/;package=${BPN};version=${PV} \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"
```

**shrinkwrap 생성 방법:**

```bash
# devtool이 자동으로 생성
devtool add <package-name> "npm://registry.npmjs.org/;package=<name>;version=<ver>"

# 생성된 파일들:
# - recipes-*/<name>/<name>_<ver>.bb
# - recipes-*/<name>/<name>/npm-shrinkwrap.json
```

### 2. Git 소스 + NPM 의존성

```bitbake
inherit npm

SRC_URI = " \
    git://github.com/example/project.git;branch=main;protocol=https \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"
SRCREV = "abc123..."
```

### 3. Python 패키지 (pip)

```bitbake
# ❌ 금지: 빌드 시 pip install
# ✅ 필수: inherit pypi 또는 로컬 소스 사용
```

### 4. 일반 소스 패키지

```bitbake
# ✅ 체크섬 필수
SRC_URI = "https://example.com/package-${PV}.tar.gz"
SRC_URI[sha256sum] = "abc123..."
```

## 라이센스 체크섬 정책

모든 의존성의 라이센스 파일을 명시적으로 체크:

```bitbake
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464 \
    file://node_modules/mqtt/LICENSE;md5=261aa46f11e9a7bdbea1dea7eb8bcb6c \
    file://node_modules/winston/LICENSE;md5=124783bb03d1b801c23d11f07b62be0a \
"
```

**이유:**
- Yocto가 라이센스 변경을 자동 감지
- 법적 컴플라이언스 자동화
- 보안 취약점 추적 용이

## 디렉토리 구조

```
meta-homeagent/
├── conf/
│   └── layer.conf
└── recipes-connectivity/
    └── zigbee2mqtt/
        ├── zigbee2mqtt_2.4.0.bb        # inherit npm
        ├── zigbee2mqtt_%.bbappend      # systemd 등 추가 설정
        └── zigbee2mqtt/
            ├── npm-shrinkwrap.json     # devtool로 생성
            └── zigbee2mqtt.service     # systemd 서비스
```

## 신규 레시피 체크리스트

새로운 .bb 파일을 추가할 때 확인:

- [ ] `npm://` 사용 시 `npmsw://` shrinkwrap 파일 포함?
- [ ] 모든 `SRC_URI`에 체크섬 있음?
- [ ] `LIC_FILES_CHKSUM`에 모든 라이센스 포함?
- [ ] 네트워크 접속하는 `do_compile()` 없음?
- [ ] `devtool add`로 생성한 경우 결과물 검토 완료?

## 버전 업그레이드 절차

```bash
# 1. 새 버전으로 devtool 실행
devtool add zigbee2mqtt "npm://registry.npmjs.org/;package=zigbee2mqtt;version=2.5.0"

# 2. 생성된 shrinkwrap 비교
diff old/npm-shrinkwrap.json new/npm-shrinkwrap.json

# 3. 라이센스 변경 확인
# (새로운 의존성에 GPL 등 주의 필요한 라이센스 있는지)

# 4. 레시피 파일 업데이트
# - 버전 번호
# - SRCREV (git 사용 시)
# - LIC_FILES_CHKSUM
```

## 참고 자료

- [Yocto 3.1 Migration Guide - npm changes](https://docs.yoctoproject.org/migration-guides/migration-3.1.html)
- [Yocto NPM Tips & Tricks](https://wiki.yoctoproject.org/wiki/TipsAndTricks/NPM)
- [Yocto Working with Packages](https://docs.yoctoproject.org/dev/dev-manual/packages.html)
- [domotik-or/yocto-domotik](https://github.com/domotik-or/yocto-domotik) - zigbee2mqtt 2.4.0 참고 구현

## 레퍼런스 레시피

### 좋은 예: domotik-or zigbee2mqtt

```bitbake
inherit npm

SRC_URI = " \
    npm://registry.npmjs.org/;package=zigbee2mqtt;version=${PV} \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"

# 모든 의존성 라이센스 명시 (150+ 항목)
LIC_FILES_CHKSUM = "file://LICENSE;md5=... \
    file://node_modules/@babel/runtime/LICENSE;md5=... \
    ..."
```

### 참고할 레이어

| 레이어 | 패턴 | 참고 포인트 |
|--------|------|-------------|
| [meta-homebridge](https://github.com/leon-anavi/meta-homebridge) | npm + systemd | Node.js 앱 서비스화 |
| [domotik-or/yocto-domotik](https://github.com/domotik-or/yocto-domotik) | npmsw | 최신 zigbee2mqtt |

---

**원칙: 복잡도는 비용이 아니라 가치다.**

`npm ci`는 "개발 편의"이고, `npmsw`는 **"제품 수준 엔지니어링"**이다.
