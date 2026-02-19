# HomeAgent 세팅 가이드

> RPi5 + Yocto scarthgap 5.0 LTS 기반 오프라인 퍼스트 IoT 허브
> 이 문서대로 따르면 클린 상태에서 동작하는 RPi5까지 재현 가능

## 전제 조건

- NixOS 또는 Nix 패키지 매니저 (nixpkgs **unstable** 사용)
- SD 카드 리더 (또는 원격 플래싱용 호스트)
- RPi5 + 5V/5A 이상 전원 공급기 (USB 동글 안정성 필수)
- ZBDongle-E (Thread RCP 펌웨어 플래시 완료)

## 0. 리포 클론

```bash
git clone git@github.com:junghan0611/homeagent-config.git
cd homeagent-config
```

## 1. Yocto 레이어 설정 (첫 클론 시만)

```bash
./run.sh layers          # 레이어 git clone (첫 실행 시만)
./run.sh layers --link   # 또는 기존 ~/repos/3rd/ 클론을 심볼릭 링크
./run.sh status          # 레이어 브랜치 확인 (이미 있으면 이것만)
```

> `yocto/sources/`에 레이어가 이미 있으면 **스킵**. `./run.sh status`로 확인만 하면 됨.

레이어 목록:

| 레이어 | 브랜치 | 용도 |
|--------|--------|------|
| poky | scarthgap | Yocto 기본 |
| meta-openembedded | scarthgap | meta-oe, meta-python, meta-networking |
| meta-raspberrypi | scarthgap | RPi5 BSP |
| meta-clang | scarthgap | Flutter 빌드용 |
| meta-hailo | hailo8-scarthgap | NPU 지원 (미활성) |
| meta-homeagent | - | 커스텀 레시피 (이 리포 내) |

## 2. 빌드 설정 확인

`yocto/build/conf/` 디렉토리에 설정 파일이 이미 있음:

- `local.conf` — MACHINE=raspberrypi5, systemd, openssh, opkg 등
- `bblayers.conf` — 레이어 경로

핵심 설정 (local.conf):

```
MACHINE = "raspberrypi5"
IMAGE_INSTALL:append = " ot-br-posix avahi-daemon avahi-utils"
EXTRA_IMAGE_FEATURES += "package-management"  # opkg
IMAGE_ROOTFS_EXTRA_SPACE = "1048576"          # +1GB 여유
```

## 3. 빌드

```bash
./run.sh bb              # Nix FHS 환경 자동 진입 → bitbake core-image-weston
```

- 첫 빌드: 수 시간 소요 (sstate-cache 없을 때)
- 재빌드: bbappend 변경분만 빌드 (수 분)
- 빌드 결과: `yocto/build/tmp-glibc/deploy/images/raspberrypi5/core-image-weston-raspberrypi5.rootfs.wic.bz2`

### bbappend 수정 후 재빌드

bbappend 파일(예: `ot-br-posix_git.bbappend`)을 수정한 경우,
sstate 캐시가 변경을 감지하지 못할 수 있다. **반드시 cleansstate 후 리빌드**:

```bash
./run.sh bb-cmd -c cleansstate ot-br-posix   # 캐시 무효화
./run.sh bb                                   # 리빌드 (필수!)
./run.sh flash /dev/sdX                       # 플래싱
```

> **주의**: `cleansstate`만 하고 `bb`를 빠뜨리면 이전 이미지가 그대로 플래싱된다.

### 빌드 관련 명령

```bash
./run.sh bb              # 기본 빌드 (core-image-weston)
./run.sh bb-clean        # tmp-glibc 삭제 후 클린 빌드
./run.sh bb-resume       # 중단된 빌드 이어서
./run.sh bb-cmd -c cleansstate <recipe>  # 특정 레시피 sstate 캐시 삭제
./run.sh bb-cmd -e nodejs    # bitbake 임의 명령
./run.sh image           # 빌드된 이미지 정보 확인
```

### nixpkgs 주의

**반드시 unstable 사용.** 25.11 전환 시 glibc 2.42 sstate 불일치 발생.

## 4. SD 카드 플래싱

```bash
./run.sh flash /dev/sdX              # 로컬 SD 카드 리더
./run.sh deploy 192.168.0.118        # 원격 호스트로 전송 후 플래싱
```

bmaptool 사용 (Nix에서 자동 설치).

## 5. 첫 부팅 + SSH 접속

```bash
# IP 설정 (RPi5 이더넷 연결 후 IP 확인)
./run.sh set-ip <RPi5-IP>

# SSH 키 최초 등록 (비밀번호: homeagent)
./run.sh setup-key

# 접속
./run.sh ssh
```

## 6. 부팅 후 자동 설정 (bbappend 적용됨)

reflash 후 다음 서비스가 **자동으로** 구성됨:

| 서비스 | 설정 | 자동 |
|--------|------|:----:|
| otbr-agent | eth0 backbone, ttyUSB0, 460800 baud | ✅ |
| otbr-srp-enable | SRP server 자동 활성화 | ✅ |
| avahi-daemon | mDNS/DNS-SD | ✅ |
| openssh | SSH 서버 | ✅ |
| opkg | 런타임 패키지 관리자 | ✅ |

### 수동 작업 필요 항목

```bash
# SSH 키 재등록 (reflash 후 호스트키 변경)
./run.sh setup-key

# Thread 네트워크 생성 (첫 부팅 시 1회)
ot-ctl dataset init new
ot-ctl dataset commit active
ot-ctl ifconfig up
ot-ctl thread start
# 8초 대기 후 leader 확인
ot-ctl state                          # → leader

# SRP server 재활성화 (Thread 시작 후 상태 리셋됨)
systemctl restart otbr-srp-enable
ot-ctl srp server state               # → running
```

## 7. 검증

```bash
# SSH 접속 후 RPi5에서 실행:
ot-ctl state                  # → leader
ot-ctl srp server state       # → running (자동 enable됨)
avahi-browse -apt              # → _meshcop._udp 등 확인
systemctl status otbr-agent   # → active (running)
```

## 8. Matter Commissioning (chip-tool)

```bash
# 호스트에서 chip-tool 빌드 + 배포
./run.sh build-chip-tool
./run.sh deploy-chip-tool

# RPi5에서 commissioning
chip-tool pairing code-thread <node-id> hex:<dataset> <setup-code> --bypass-attestation-verifier true

# 데이터 읽기 예시 (Eve 도어센서)
chip-tool booleanstate read state-value <node-id> 1
```

- chip-tool: **반드시 v1.4.0.0 + Docker tag 81** (glib 호환)
- `--bypass-attestation-verifier true` 필수

## 9. 다음 단계 (현재 진행 중)

| 태스크 | 상태 | 명령 |
|--------|------|------|
| ha-2ob: matterjs-server 빌드 검증 | 레시피 완료, 빌드 미검증 | `./run.sh npm-build matterjs-server` |
| ha-cuj: z2m 2.8.0 업그레이드 | 대기 | `./run.sh npm-shrinkwrap zigbee2mqtt` |
| ha-1kl: npmsw 오프라인 빌드 전환 | 대기 | - |
| ha-tan: Go HomeAgent 컨트롤러 | 대기 | `./run.sh go-build` |

## 전체 흐름 요약

```
git clone → (./run.sh layers) → ./run.sh bb → ./run.sh flash
→ 부팅 → ./run.sh setup-key → ./run.sh ssh
→ Thread 네트워크 생성 → SRP 자동 → Matter commissioning 준비 완료

재빌드 시: ./run.sh bb → ./run.sh flash → ./run.sh setup-key → 끝
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| CP210x `request 0x12 status: -110` | RPi5 전원 부족 | 5V/5A 이상 전원 사용 |
| HDLC frame parse error | USB 포트 문제 | 블루 USB3 포트에 연결 |
| SRP server disabled | 서비스 타이밍 | 30초 대기 후 재확인 (자동 retry) |
| chip-tool `g_once_init_enter_pointer` | glib 2.80 비호환 | v1.4.0.0 + tag 81 사용 |
| SSH 접속 실패 (host key 변경) | reflash 후 호스트키 리셋 | `./run.sh setup-key` |
| bbappend 수정이 반영 안 됨 | sstate 캐시 재사용 | `bb-cmd -c cleansstate <recipe>` 후 `bb` |
| cleansstate 후 플래시했는데 변경 없음 | 리빌드 누락 | `cleansstate` → **`bb`** → `flash` 순서 필수 |
