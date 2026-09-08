# RUNBOOK — 새 SMHub Nano를 받아서 domoticz가 돌기까지

**이 문서는 "순서"다.** 왜 이렇게 하는지는 [`smhub/README.md`](README.md), 기기의 측정된 사실은
[`docs/SMHUB.md`](../docs/SMHUB.md), 지금 어디까지 왔는지는 [`NEXT.md`](../NEXT.md)에 있다.
셋은 역할이 다르고 서로를 복사하지 않는다:

| 문서 | 답하는 질문 | 여기 없는 것 |
|---|---|---|
| `docs/SMHUB.md` | 이 기기는 **무엇인가** (실측 SSOT) | 절차 |
| `smhub/README.md` | 이 레인은 **왜** 이렇게 하나 (전략·판정) | 절차 |
| **`smhub/RUNBOOK.md` (이 문서)** | **무엇을 어떤 순서로 치나** | 배경 설명 |

새 기기 한 대에 대해 **위에서 아래로 한 번** 통과한다. 각 단계는 **판정(어떻게 성공을 아는가)**
을 달고 있다 — 이 레인은 "성공 출력이 생존의 증거가 아닌" 자리를 반복해서 만났기 때문이다.

> 상태 표기: ✅ = 실기로 통과 확인, ⚠️ = 함정 있음(읽고 치라), ❓ = 아직 미검증.

## 증거 경계 (2026-09-08) — 먼저 읽어라

이 문서는 **완료 보고가 아니라 통과시키기 위한 절차**다. 지금까지 실기로 확인된 곳과 아닌 곳:

| 단계 | 상태 |
|---|---|
| §2 SSH 복구 (접속 + p7 캐시 정상) | ✅ 한 유닛 |
| §3 ABI 측정 → base 태그 판정 | ✅ 한 유닛 |
| §4 빌드 → riscv64 바이너리 | ✅ 한 유닛 |
| §5 `.ipk` 생성 (기기에 물어 번들 도출) | ✅ 한 유닛 |
| **§2 리부트/OTA를 건넌 SSH 지속** | **❓ 미실행** |
| **§6 설치 · OpenRC 기동 · HTTP 응답** | **❓ 미실행** |
| **§6 리부트 후 자동 재기동** | **❓ 미실행** |
| **§7 1코어 CPU/RSS 실측** | **❓ 미실행** |

**"domoticz가 돈다"는 아직 아무도 보지 못했다.** ❓ 단계를 통과시키는 사람이 이 표를 갱신한다.

---

## 0. 준비물

| 항목 | 값 |
|---|---|
| 기기 | SMHub Nano Mg24 (SG2000, riscv64, MG24 온보드) |
| 호스트 | Linux + docker + git (NixOS 가정, `/usr/bin/file` 없어도 됨 — 컨테이너가 해결) |
| 디스크 | Buildroot 트리 ~15GB |
| 시간 | 첫 빌드 **4~5시간** (대부분 domoticz 소스 내려받기, §4 참조) |
| 네트워크 | 기기와 **같은 서브넷** 유선 |
| 좌표 | IP·계정·피드 인증 = `PRIVATE.md` (공개 파일에 쓰지 않는다) |

### 0.1 없으면 STOP — 문서로 대체할 수 없는 입력

- **Web UI 관리자 계정.** OS `1.0.2`부터 Web UI가 인증을 요구하고, 이건 **셸 계정(`smlight`)과
  다른 계정**이다. 셸 암호로 대체되지 않는다. 초기 생성/복구 경로는 벤더/판매자 인계나
  `PRIVATE.md`에서 받는다 — **없으면 §2의 Web Console에 도달할 수 없어 진행 불가다.**
- **지원 OS 프로파일.** 지금 검증된 프로파일은 **`1.0.2` 하나**다. 기기의 `VERSION_ID`가 다르면
  §3으로 가서 ABI를 다시 재고, base 태그를 다시 정해야 한다(§3의 판정 규칙).

### 0.2 클라이언트 키 (없으면 만든다)

`.sshkey/`는 의도적으로 gitignore다 — 새 클론에는 **없다**.

```bash
install -d -m 700 .sshkey
[ -f .sshkey/id_ed25519 ] || ssh-keygen -t ed25519 -f .sshkey/id_ed25519 -N '' -C smhub-domoticz
```

---

## 1. 기기 올리기 — 전원·네트워크·Web UI ✅

유선 연결 후 DHCP 주소를 찾는다. mDNS가 `smhub.local`로 뜬다.

```bash
ping -c2 smhub.local            # 또는 PRIVATE.md의 고정 IP
curl -sI http://smhub.local     # nginx 200/302 = Web UI 살아 있음
```

**판정**: Web UI가 뜬다. 벤더 로그인 화면이 나오면 정상이다 — OS `1.0.2`부터 Web UI가
**인증을 강제한다**(beta5는 무인증이었다). 셸 계정(`smlight`)과 **다른 계정**이니 셸 암호를
넣지 마라.

---

## 2. SSH 열기 ⚠️ — 이 레인 최대의 삽질 자리

기본 상태에서 `:22`는 refused다. Web UI에서 SSH를 켜도 **여전히 안 붙는 경우가 있고**, 그게
정상 동작이 아니라 **벤더 init의 결함**이다.

### 2.1 증상

`rc-status`는 `sshd [started]`라고 말하는데 접속은 refused. `/etc/ssh/ssh_host_*_key`가
**0바이트**이고 날짜가 과거(예: `Dec 11 2025`)로 되돌아와 있다. 직접 `ssh-keygen -A`를 해도
sshd를 재시작하면 다시 0바이트로 돌아온다.

### 2.2 원인

`/etc/init.d/sshd`의 `start_pre()`가 host key를 **p7 `/mnt/user/ssh`에 캐시**하고 매 기동
`cp -p`로 `/etc/ssh`에 복원한다. 의도는 OTA 생존인데, **0바이트 키가 그 캐시에 영속화되면**
우리가 만든 키를 sshd 기동 직전에 매번 덮는다. (`cp -p`가 mtime까지 보존해서 날짜가
되살아나는 것이다.)

### 2.3 해법 — 벤더 경로를 그대로 쓰는 한 줄

Web UI → Console(Web Terminal)에서:

```sh
sudo rm -f /mnt/user/ssh/ssh_host_* /etc/ssh/ssh_host_*; sudo rc-service sshd restart
```

캐시가 비면 init의 else 분기가 스스로 `ssh-keygen -A` + p7 저장을 한다. 이렇게 하면
**재발 조건(0바이트 캐시)이 제거된다** — 다만 리부트를 실제로 건넌 확인은 §6에서 한다.

### 2.4 클라이언트 키 등록

```bash
ssh-copy-id -i .sshkey/id_ed25519.pub smlight@<기기>     # 벤더 기본 암호는 PRIVATE.md
ssh -i .sshkey/id_ed25519 smlight@<기기> 'hostname; uname -m'
```

**판정 (두 개를 다 봐라)**:

```bash
# ① 붙는다
ssh -i .sshkey/id_ed25519 smlight@<기기> 'echo OK'
# ② 캐시가 0바이트가 아니다  = 다음 부팅에도 산다
ssh -i .sshkey/id_ed25519 smlight@<기기> 'ls -l /mnt/user/ssh/'
```

②의 키가 505/399/2590 바이트 수준이면 결함이 제거된 것이다. ①만 보고 넘어가면 **다음
리부트에서 되돌아온다** — 그게 이 함정의 본질이다.

> 상태: 우리 유닛은 2026-09-08 ①②를 통과했다. **리부트를 실제로 건넌 실증은 ❓ 미검증** —
> 다음 리부트/OTA 때 ②를 한 번 더 보면 `docs/SMHUB.md` §3.6이 완전히 닫힌다.

---

## 3. 기기 ABI 좌표 측정 ✅ — 빌드 전에 **반드시** 한다

우리가 만들 건 **기기 ABI에 못박힌 바이너리**다. 그래서 빌드 base는 문서가 아니라 **이 기기**가
정한다. OS를 업데이트할 거라면 **업데이트를 먼저 하고** 여기서 측정하라(끝나고 올리면 base가
움직여 바이너리가 무효가 된다).

```bash
ssh -i .sshkey/id_ed25519 smlight@<기기> '
  cat /etc/os-release | grep -E "^VERSION|^PRETTY"
  uname -m
  /lib/libc.so.6 | head -1                       # glibc  ← base 태그를 정하는 값
  readlink -f /usr/lib/libstdc++.so.6            # libstdc++
  python3 -V
  nproc; free -m | head -2
'
```

우리 유닛(2026-09-08, OS `1.0.2`):

| 축 | 값 |
|---|---|
| Buildroot rev | `2026.02-1281-g9407f694e5` (벤더 커밋 1281개 — upstream엔 없다) |
| **glibc** | **2.42** ← **이 값 하나가 base 태그를 정한다** |
| GCC / libstdc++ | 15.2.0 / `libstdc++.so.6.0.34` |
| Python | 3.14.6 (soname `libpython3.14.so.1.0`) |
| CPU / RAM | **`nproc` 1** · MemTotal 488M |

**판정 규칙**: upstream Buildroot 태그 중 **glibc가 같은 것**을 고른다. 여기서는 `2026.02`.
bit-identical 재현은 벤더 커밋 때문에 불가하지만 **ABI 재현은 가능하고, 그게 필요한 전부다.**
더 새 buildroot(master, glibc 2.44)로 빌드하면 기기에서 **아예 시작하지 않는다.**
`setup.sh`가 이 핀을 검증하고 어긋나면 멈춘다.

### 3.5 ⚠️ preflight — 이 값들은 기기마다 다르다. 빌드 전에 재라

아래는 **문서에서 읽으면 안 되는 값**이다. 우리 유닛에서 OTA 한 번에 바뀐 실적이 있다
(1.0.2가 z2m을 2.13.0으로 올리고 켰다). 새 유닛에서 직접 봐라:

```bash
ssh -i .sshkey/id_ed25519 smlight@<기기> '
  ss -ltn                       # 8081이 비었나  (8080은 z2m이 쓴다)
  pgrep -af zigbee2mqtt || true # z2m이 도는가
  ls -l /dev/ttyS1              # 라디오
  rc-status --all | head -30
'
```

분기:

- **8081이 차 있으면** → 포트를 바꿔서 패키징한다. **기기에서 고치지 마라** — 다음 ipk가
  되돌린다. `HOMEAGENT_SMHUB_HTTP_PORT=8083 ./smhub/pack-ipk.sh` (§5).
- **z2m이 돌고 있으면** → 그게 `/dev/ttyS1`을 쥔다. domoticz만 올리는 데는 문제없다(§6.2).
  Z4D로 Zigbee를 할 때 비로소 결정할 일이다.

### 3.6 ⚠️ 빌드 전 1분 점검 — 4시간을 버리지 않으려면

§4.4의 cmake 함정은 **다운로드 3.5시간이 끝난 뒤에** 터진다. 그 전에 확인해라:

```bash
grep -c Python3_INCLUDE_DIR smhub/package/domoticz/domoticz.mk   # 1 이면 우회 살아 있음
```

`0`이 나오면 §4.4를 먼저 읽어라. domoticz 버전을 올렸다면 이 우회가 여전히 필요한지도 같이 본다.

---

## 4. 빌드 ✅

```bash
./smhub/setup.sh     # upstream Buildroot 2026.02 클론 + glibc 핀 검증 (한 번)
./smhub/build.sh     # 입력 주입 → make domoticz
```

`build.sh`는 매번 `smhub/buildroot/*_defconfig`와 `smhub/package/domoticz/`를 트리에 주입한다.
**트리(`smhub/sdk/`)는 gitignore이고 SSOT가 아니다** — 고칠 것은 항상 `smhub/` 쪽이다.

### 4.1 실측 소요 (랩탑 16코어)

| 단계 | 시간 |
|---|---|
| 호스트 툴 8개 | ≈13분 |
| 크로스 툴체인 (binutils 2.44 · GCC 15.2 · glibc 2.42) + boost + python3 | ≈1시간 |
| **domoticz 소스 다운로드** | **3시간 28분** ⚠️ |
| domoticz 컴파일+설치 | **2분 55초** |

⚠️ **다운로드가 컴파일의 70배다.** `SITE_METHOD=git` + `GIT_SUBMODULES=YES`로 전체 히스토리와
서브모듈 5개를 받기 때문이다(서브모듈은 회피 불가 — 태그 타르볼의 `extern/`은 빈 디렉터리이고
`extern/libwebem`은 `add_subdirectory`가 무조건 걸려 있다). **`dl/`에 캐시되므로 두 번째부터는
안 문다.** 다른 호스트로 옮길 때 `smhub/sdk/dl/`을 같이 옮기면 3.5시간을 아낀다.

### 4.2 중단·재개

Buildroot는 `output/build/*/.stamp_*`로 단계를 기억한다. 랩탑이 잠들거나 빌드를 죽여도
`./smhub/build.sh` 한 번이면 **그 패키지부터** 이어간다.

⚠️ **컨테이너는 감독 프로세스보다 오래 산다.** 재시작 전에 확인하지 않으면 두 make가 같은 트리를 쓴다:

```bash
docker ps --filter ancestor=milkvtech/milkv-duo:latest   # 남아 있으면 docker kill <id>
```

⚠️ **호스트와 컨테이너를 섞어 굽지 마라.** 호스트에서 만든 `buildroot-config/conf`는 nix 로더에
링크돼 컨테이너에서 `Error 127`로 죽는다. 섞였으면 `rm -rf smhub/sdk/output`.

### 4.3 판정

```bash
readelf -d smhub/sdk/output/target/opt/domoticz/domoticz | grep NEEDED
file      smhub/sdk/output/target/opt/domoticz/domoticz
```

기대값: `ELF 64-bit LSB pie executable, UCB RISC-V, RVC, double-float ABI`,
인터프리터 `/lib/ld-linux-riscv64-lp64d.so.1`. **"빌드됐다"의 사실원은 이 두 줄이지 make의
종료코드가 아니다.**

### 4.4 ⚠️ 알려진 함정 — cmake가 Python3를 못 찾는다

domoticz 2026.3은 `find_package(Python3 3.4 COMPONENTS Development)`를 쓴다
(`CMakeLists.txt:508`). FindPython3는 **타깃 인터프리터**에서 탐색을 시작하는데 크로스빌드엔
그게 없어서, sysroot에 헤더와 `.so`가 멀쩡히 있어도 이렇게 죽는다:

```
CMake Error: Python3 not found on your system, use USE_PYTHON=NO or sudo apt-get install python3-dev
```

**`USE_PYTHON=NO`로 끄지 마라** — 그게 Z4D(Zigbee 플러그인)를 가능하게 하는 유일한 스위치다.
해법은 캐시 변수를 직접 물려주는 것이고, **이미 `smhub/package/domoticz/domoticz.mk`에 들어
있다**(`Python3_INCLUDE_DIR` / `Python3_LIBRARY`). 성공하면 configure 로그에 이 줄이 뜬다:

```
-- Found Python3: .../include/python3.14 (found suitable version "3.14.3") found components: Development Development.Module Development.Embed
```

> 참고: Python은 **NEEDED에 안 잡힌다.** domoticz는 `libpython3.x`를 **dlopen**한다
> (바이너리 안의 `Py_*` 심볼 143개 + "Failed dynamic library load" 문자열이 근거).
> 그러니 NEEDED에 없다고 해서 Python이 꺼진 게 아니다 — 판정은 위 configure 로그로 한다.

---

## 5. 패키징 ✅

```bash
SMHUB_SSH="smlight@<기기>" ./smhub/pack-ipk.sh
```

**번들 목록을 문서에서 읽지 않는다.** 스크립트가 ① 바이너리의 NEEDED 폐포를 `readelf`로 구하고
② **살아 있는 기기에 SSH로 물어** 이미 있는 걸 뺀다. SSH가 없으면 **추측하지 않고 멈춘다** —
한 프로세스에 같은 soname이 두 벌 들어가는 게 최악이기 때문이다.

우리 유닛 실측(2026-09-08): 폐포 15개 중 **기기가 13개를 제공**, 동봉은 **2개뿐**.

| 동봉 (기기에 없음) | 기기 rootfs 사용 |
|---|---|
| `libboost_thread.so.1.83.0` · `liblua.so.5.3.6` | `libsqlite3.so.0` · `libssl/libcrypto.so.3` · `libcurl.so.4` · **`libmosquitto.so.1`** · `libz` · `libresolv` · `libm` · `libatomic` · `libc` · `libstdc++.so.6` · `libgcc_s.so.1` · `ld-linux-riscv64-lp64d.so.1` |

- `libsqlite3`: 기기 실물은 `libsqlite3.so.3.53.2`지만 **`.so.0` 심링크가 있어** soname이 맞는다.
  동봉 불필요.
- `libpython3.14.so.1.0`: 기기에 있다 → **Z4D 전제 충족.**
- jsoncpp·minizip·jwt-cpp·libwebem은 **바이너리에 정적 내장**이라 목록에 없다.

포트를 바꿔야 하면 여기서 준다(§3.5):

```bash
HOMEAGENT_SMHUB_HTTP_PORT=8083 SMHUB_SSH="smlight@<기기>" ./smhub/pack-ipk.sh
```

**산출물**: `smhub/out/domoticz_<ver>-<rev>_riscv64.ipk` + `.manifest.txt`. 매니페스트가 재현의
영수증이고, 다음을 담는다:

```
sha256 / domoticz 버전 / br-commit(40자리) / domoticz-src(소스 tarball sha256)
build-image-digest / http-port / required-os / 동봉 목록 / rootfs 제공 목록
--- device profile ---  os_version · buildroot rev · arch · glibc · libstdc++ · python · nproc
```

- **`domoticz-src`가 진짜 provenance다.** 태그 이름(`2026.3`)은 provenance가 아니다 — 이 sha256이
  superproject와 서브모듈 5개 리비전을 함께 덮는다.
- **`.ipk`는 이 device profile에 대해서만 유효하다.** 번들 목록이 기기 함수이기 때문이다.
  `Required-OS-Version`은 빌드한 프로파일(`1.0.2`)이지, 파일을 받아줄 가장 낮은 OS가 아니다.
  기기 OS가 다르면 `pack-ipk.sh`가 경고한다.

---

## 6. 설치·기동 ❓ 미검증

> 여기부터는 아직 실기로 통과시키지 않았다. 절차는 §3.7 패턴 (a)에서 도출한 것이고,
> 처음 밟는 사람이 판정을 직접 봐야 한다.

```bash
scp -i .sshkey/id_ed25519 smhub/out/domoticz_*_riscv64.ipk smlight@<기기>:/tmp/
ssh -i .sshkey/id_ed25519 smlight@<기기> 'sudo opkg install /tmp/domoticz_*_riscv64.ipk'
ssh -i .sshkey/id_ed25519 smlight@<기기> 'sudo rc-update add domoticz default && sudo rc-service domoticz start'
```

**판정 — 셋 다 봐라. `rc-status`는 사실원이 아니다.**

```bash
ssh ... 'opkg list-installed | grep domoticz'      # ① 설치됨
ssh ... 'pgrep -a domoticz'                        # ② 프로세스 살아 있음
ssh ... 'ss -ltn | grep 8081'                      # ③ 실제로 듣고 있음
curl -sI http://<기기>:8081                        # ④ 밖에서 응답
```

**그리고 리부트를 건너라. 이게 판정의 절반이다.**

```bash
ssh ... 'sudo reboot'        # ~100초
# 돌아온 뒤: ①②③④를 그대로 반복 + SSH가 여전히 붙는지(§2.4 ②)
ssh -i .sshkey/id_ed25519 smlight@<기기> 'ls -l /mnt/user/ssh/; uptime'
```

리부트 전만 보면 **두 가지를 동시에 놓친다**: `rc-update`가 실제로 영속했는지, 그리고 §2의
host key 복구가 진짜였는지. 둘 다 이 한 번으로 닫힌다.

실패하면 되돌리는 길:

```bash
ssh ... 'sudo rc-service domoticz stop; sudo opkg remove domoticz'
ssh ... 'logread | tail -50'     # 또는 /var/log
```

### 6.1 ⚠️ 포트 — 8080은 비어 있지 않다

벤더 z2m 프론트엔드가 **8080을 이미 쓴다**(`/opt/bin/node /opt/bin/zigbee2mqtt`, 실측
2026-09-08). 그래서 우리 init 스크립트는 **8081**을 쓴다. 새 기기에서 8081도 차 있으면
`/etc/init.d/domoticz`의 `-www` 값을 바꾸고, `pack-ipk.sh` 쪽도 같이 고쳐라(**기기에서만 고치면
다음 ipk에서 되돌아온다**).

### 6.2 ⚠️ 라디오는 하나뿐이다

`/dev/ttyS1`(MG24, EmberZNet 7.4.2 / EZSP 13)을 **z2m이 잡고 있다**. 우리 패키지는 그 포트를
건드리지 않는다. Z4D로 Zigbee를 하려면 **z2m을 먼저 내려야 하고**, 그건 이 패키지가 대신
결정하지 않는다 — 한 라디오, 한 호스트 스택.

```bash
ssh ... 'sudo rc-service zigbee2mqtt stop'    # 필요할 때, 의식적으로
```

### 6.3 설치면

`/opt`는 **p7(`/dev/mmcblk0p7`, ext4 rw)**이고 **OTA가 건드리지 않는다.** rootfs는 ro + A/B라
설치면이 아니다. `/home`·`/var`도 같은 p7이다. 여유는 5.2G/5.7G.

---

## 7. 측정 ❓ — 이 레인이 실제로 답해야 하는 질문

기동이 확인되면 **여기가 목적지다.** `nproc`이 1이고 RAM이 488M인 기기에서:

```bash
ssh ... 'top -bn2 | grep -E "domoticz|Mem"; cat /proc/$(pgrep domoticz)/status | grep VmRSS'
```

답해야 할 값: **1코어가 세트 하나(30~40대)를 받는가.** 이게 works-nixos-zigbee 레인(x86 실증,
4스레드를 잠정 하한으로 적었다)에 돌려줄 값이다.

---

## 8. 실패 사전

| 증상 | 원인 | 조치 |
|---|---|---|
| `:22` refused, `rc-status`는 started | p7 캐시의 0바이트 host key | §2.3 한 줄 |
| SSH 됐는데 리부트 후 다시 refused | 캐시가 여전히 0바이트 | §2.4 ②를 봤어야 했다 |
| cmake `Python3 not found` | 크로스에 타깃 인터프리터 없음 | §4.4 (끄지 마라) |
| make `Error 127` | 호스트/컨테이너 혼용 | `rm -rf smhub/sdk/output` |
| 빌드가 이상하게 두 배 느림 | 컨테이너 두 개 | `docker ps` → `kill` |
| `setup.sh`가 glibc 핀에서 멈춤 | base 태그가 기기 ABI와 다름 | 태그를 기기 glibc에 맞춘다 (§3) |
| `pack-ipk.sh`가 SMHUB_SSH 없다고 멈춤 | 의도된 것 | 추측 금지, 기기를 붙여라 |
| `pack` 중 "neither on the device nor in our build" | defconfig에 그 라이브러리가 없다 | defconfig에 추가 후 재빌드 |
| domoticz가 떠도 8081 응답 없음 | 포트 충돌 | §6.1 |
| Z4D가 라디오를 못 연다 | z2m이 점유 | §6.2 |
| 리부트 후 domoticz가 안 뜬다 | `rc-update add`를 안 했거나 영속 실패 | §6 판정에 리부트가 있는 이유 |
| `setup.sh`가 commit pin에서 멈춤 | 트리 HEAD가 태그와 다름 | 출력의 `git checkout --detach` 한 줄 |
| ipk가 다른 기기에서 안 뜬다 | device profile 불일치 | 매니페스트의 profile과 대조(§5) |

---

## 9. 재현성 계약

- **기기에 ssh로 밀어넣어 제품을 만들지 않는다.** 설치되는 것은 `.ipk` 하나이고, 그 안의
  모든 것은 `smhub/`의 입력에서 나온다. 기기에서 직접 고친 것은 다음 ipk에서 사라진다 —
  그게 결함이 아니라 **계약**이다.
- **손으로 만든 상태를 보존하지 않는다.** 자산은 기기의 상태가 아니라 **절차**다.
  다시 만들 수 있는 것을 아끼면 재현 불가능한 특수 상태가 된다.
- **판정은 항상 사실원으로.** `readelf`/`pgrep`/`ss`/`opkg list-installed`이지,
  `rc-status`나 진행률 배너가 아니다.
