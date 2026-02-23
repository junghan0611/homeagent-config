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
# run.sh 래퍼 사용 (FHS 환경 자동 진입)
./run.sh npm-shrinkwrap matterjs-server

# 내부적으로 devtool add → shrinkwrap 복사 → workspace 정리
```

**생성 후 반드시 확인:**

```bash
# 1. optional인데 실제로는 필수인 패키지 확인
#    소스 코드에서 import "pkg"로 하드 임포트하는데
#    shrinkwrap에서 optionalDependencies인 경우 → dependencies로 이동
grep -A3 "optionalDependencies" npm-shrinkwrap.json

# 2. resolve 엔트리 존재 확인
#    optionalDependencies에 이름만 있고 node_modules/<pkg> 엔트리가
#    없으면 Yocto가 건너뜀 → npm view로 정보 조회 후 수동 추가
npm view <pkg>@<ver> dist.tarball dist.integrity
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
    ├── zigbee2mqtt/
    │   ├── zigbee2mqtt_2.4.0.bb        # inherit npm
    │   ├── zigbee2mqtt_%.bbappend      # systemd 등 추가 설정
    │   └── zigbee2mqtt/
    │       ├── npm-shrinkwrap.json     # devtool로 생성
    │       └── zigbee2mqtt.service     # systemd 서비스
    └── matterjs-server/
        ├── matterjs-server_0.3.5.bb    # inherit npm
        ├── matterjs-server_%.bbappend  # systemd + 환경 변수
        ├── matterjs-server/
        │   └── npm-shrinkwrap.json     # devtool로 생성
        └── files/
            ├── matterjs-server.service # systemd 서비스
            └── matterjs-server.default # 환경 변수 (/etc/default/)
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

## 트러블슈팅

### `ERR_MODULE_NOT_FOUND` — optional 패키지 누락

**증상**: RPi5에서 서비스 시작 시 `Cannot find package '@matter/nodejs-ble'`

**원인**: npm-shrinkwrap.json에 해당 패키지의 resolve 엔트리가 없음. `optionalDependencies`에 이름만 있고 `node_modules/<pkg>` 아래 다운로드 정보(resolved, integrity)가 없으면 Yocto의 npm fetcher가 건너뜀.

**해결**:

```bash
# 1. npm registry에서 패키지 정보 확인
npm view @matter/nodejs-ble@<version> dist.tarball dist.integrity

# 2. shrinkwrap에 resolve 엔트리 추가
# node_modules/@matter/nodejs-ble: { version, resolved, integrity, dependencies }

# 3. 참조하는 패키지의 optionalDependencies → dependencies로 이동
# (코드에서 하드 import하면 optional이 아닌 필수)

# 4. cleansstate 후 재빌드
./run.sh bb-cmd -c cleansstate <recipe> && ./run.sh bb
```

**핵심 원리**: shrinkwrap의 optional은 "설치 실패해도 빌드 계속"이라는 npm 시맨틱. 하지만 소스 코드가 `import "pkg"`로 정적 임포트하면 런타임에 필수. monorepo에서 흔한 불일치 — 개발 호스트에서는 모두 설치되어 안 터지고, 크로스빌드에서만 터진다.

### `Architecture did not match` — prebuild 바이너리 QA 에러

**증상**: `do_package_qa`에서 `Architecture did not match (x86-64, expected AArch64)` 에러

**원인**: npm 네이티브 패키지가 `prebuilds/` 디렉토리에 모든 플랫폼 바이너리를 번들. Node.js는 런타임에 맞는 것만 로드하지만 Yocto QA는 타겟 외 바이너리를 거부.

**해결**: bbappend의 `do_install:append`에서 타겟 외 prebuilds 제거:

```bash
# RPi5 = AArch64 → linux-arm64만 유지
for dir in $(find ${D}${prefix}/lib/node_modules -type d -name "prebuilds"); do
    find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name "linux-arm64" -exec rm -rf {} +
done
```

`INSANE_SKIP += "arch"`로 우회 가능하지만 권장하지 않음 — 이미지 크기 낭비 + 실제 아키텍처 문제 감지 불가.

### `buildpaths` WARNING — 빌드 경로 노출

**증상**: `File ... contains reference to TMPDIR [buildpaths]`

**원인**: node-gyp 빌드 메타데이터(`.target.mk`)에 빌드 호스트 경로가 남음.

**조치**: 런타임 무영향. WARNING이므로 무시 가능. 필요 시 `do_install`에서 `.target.mk` 삭제.

### bbappend 미적용 — layer.conf 누락

**증상**: bbappend에 설정한 값(ttyUSB0, baudrate 등)이 무시되고 기본값 사용

**원인**: `layer.conf`의 `BBFILES`에 `*.bbappend` 패턴 누락

**해결**: `layer.conf`에 두 패턴 모두 포함 확인:

```
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"
```

### IMAGE_INSTALL 누락

**증상**: `bitbake <recipe>` 성공하지만 이미지에 패키지 없음

**원인**: `build/conf/local.conf`에 `IMAGE_INSTALL:append` 누락. `conf/local.conf.sample`(템플릿)에만 있고 실제 빌드 설정에 없는 경우.

**해결**: `build/conf/local.conf`에 추가:

```bitbake
IMAGE_INSTALL:append = " <package-name>"
```

주의: `build/conf/local.conf`은 `.gitignore` 대상이므로 `conf/local.conf.sample`도 함께 업데이트할 것.

### 이미지 sstate 캐시 — 패키지 변경이 이미지에 반영 안 됨

**증상**: `cleansstate <recipe>` → `bb` 성공, ipk 새로 생성됨. 하지만 플래시 후 RPi5에 이전 패키지가 그대로 있음.

**원인**: Yocto sstate가 이미지 레시피(`core-image-weston`)의 `do_rootfs` 결과를 캐싱. 레시피 패키지만 `cleansstate`하면 ipk는 갱신되지만, 이미지의 sstate는 여전히 유효하다고 판단하여 `do_rootfs`를 건너뜀.

**해결**:

```bash
# 레시피 + 이미지 둘 다 cleansstate
./run.sh bb-cmd -c cleansstate <recipe>
./run.sh bb-cmd -c cleansstate core-image-weston
./run.sh bb
```

**검증**: 이미지 심볼릭 링크의 타임스탬프가 갱신되었는지 확인:

```bash
ls -la yocto/build/tmp-glibc/deploy/images/raspberrypi5/core-image-weston-raspberrypi5.rootfs.wic.bz2
# → 새 날짜/시간의 .wic.bz2 파일을 가리켜야 함
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
