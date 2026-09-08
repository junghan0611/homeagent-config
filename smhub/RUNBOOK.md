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
| §2 **리부트를 건넌 SSH 지속** | ✅ **한 유닛 (2026-09-08)** |
| §3 ABI 측정 → base 태그 판정 | ✅ 한 유닛 |
| §4 빌드 → riscv64 바이너리 | ✅ 한 유닛 |
| §5 `.ipk` 생성 (기기에 물어 번들 도출) | ✅ 한 유닛 |
| §6 설치 · OpenRC 기동 · HTTP 200 | ✅ **한 유닛 (2026-09-08)** |
| §6 **리부트 후 자동 재기동** | ✅ **한 유닛 (2026-09-08)** |
| §7 유휴 RSS/CPU 실측 | ✅ **한 유닛 (2026-09-08)** |
| **§7 부하(30~40대) 등급 판정** | **❓ 미실행 — 페어링 기기가 없다** |

**`domoticz 2026.3`이 SMHub Nano(riscv64, 1코어, 488M)에서 돈다 — 2026-09-08 실측.**
남은 ❓는 **부하**다. 지금 값은 전부 페어링 0대의 유휴치이고, 이 리포 불변식 그대로
*running ≠ installed ≠ enabled ≠ working*.

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

### 0.2 이 문서의 명령 표기

아래에서 `$SSH`는 이 별칭이다. 붙여넣기 전에 한 번 선언하고 쓴다:

```bash
SSH='ssh -i .sshkey/id_ed25519 smlight@<기기>'    # <기기> 좌표는 PRIVATE.md
```

### 0.3 클라이언트 키 (없으면 만든다)

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

> 상태: 우리 유닛은 2026-09-08 ①②를 통과했고, **같은 날 리부트도 건넜다**(복귀 후 같은 키,
> `docs/SMHUB.md` §3.6 닫힘). **새 유닛에서는 재검증한다** — 이 결함은 유닛마다 걸린다.

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

**`USE_PYTHON=NO`로 끄지 말고 우회해라.** Z4D는 이 리포의 지원 경로가 아니라서 Python 플러그인이
필수는 아니지만, dlopen이라 **안 쓰면 비용이 0**이고(플러그인을 안 띄우면 CPython 인스턴스가 아예
안 뜬다) 검증된 바이너리를 4시간 다시 굽는 값이 아니다. 열어 둔 채로 둔다.
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

## 6. 설치·기동 ✅ — 한 유닛 통과, 새 유닛은 판정을 다시 밟는다

> 우리 유닛은 2026-09-08에 아래 판정을 전부 통과했다. **그건 이 절차가 옳다는 증거이지 새
> 유닛이 통과했다는 뜻이 아니다** — 판정 ①~④와 리부트는 유닛마다 다시 본다.

```bash
scp -i .sshkey/id_ed25519 smhub/out/domoticz_*_riscv64.ipk smlight@<기기>:/tmp/
$SSH 'sudo opkg install /tmp/domoticz_*_riscv64.ipk'
$SSH 'sudo rc-update add domoticz default && sudo rc-service domoticz start'
```

**판정 — 넷 다 봐라. `rc-status`는 사실원이 아니다.**

```bash
$SSH 'opkg list-installed | grep domoticz'      # ① 설치됨
$SSH 'pgrep -a domoticz'                        # ② 프로세스 살아 있음
$SSH 'ss -ltn | grep 8081'                      # ③ 실제로 듣고 있음
curl -sI http://<기기>:8081                     # ④ 밖에서 응답
```

**그리고 리부트를 건너라. 이게 판정의 절반이다.**

⚠️ **`$SSH 'sudo reboot'`는 자주 실행되지 않는다** — ssh 세션이 끊기며 같이 죽는다. 분리해서
띄우고, **:22가 실제로 닫히는지 먼저 확인한다**(안 닫히면 리부트가 안 걸린 것이다):

```bash
$SSH 'echo <sudo-pw> | sudo -S nohup sh -c "sleep 2; reboot" >/dev/null 2>&1 &'
# ① 정말 내려갔나 — 닫힘을 봐야 한다
until ! timeout 3 bash -c 'exec 3<>/dev/tcp/<기기>/22' 2>/dev/null; do sleep 3; done; echo "내려갔다"
# ② 돌아오면: 위 ①②③④를 그대로 반복 + host key가 살아남았는지(§2.4 ②)
$SSH 'ls -l /mnt/user/ssh/; uptime'
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
2026-09-08). 그래서 우리 init 스크립트는 **8081**을 쓴다.

새 기기에서 8081도 차 있으면 — **기기의 `/etc/init.d/domoticz`를 고치지 마라.** 포트는
pack-time 입력이라 기기 수정은 다음 ipk에서 사라진다. 다시 구워서 다시 깐다:

```bash
$SSH 'sudo rc-service domoticz stop; sudo opkg remove domoticz'
HOMEAGENT_SMHUB_HTTP_PORT=8083 SMHUB_SSH="smlight@<기기>" ./smhub/pack-ipk.sh
# 새 ipk로 §6 처음부터 다시
```

### 6.2 ⚠️ 라디오는 하나뿐이다

`/dev/ttyS1`(MG24, EmberZNet 7.4.2 / EZSP 13)을 **z2m이 잡고 있다. 그대로 둔다.**

**Zigbee 호스트는 Z2M이다 (GLG 결정 2026-09-08, RAIL 10).** domoticz는 Zigbee를 직접 물지 않고
**MQTT로 받는다** — 그게 domoticz의 표준 경로다(`hardware/MQTTAutoDiscover.cpp`가 유일한
Zigbee 입구). 그래서 이 배치는 경쟁이 아니라 **분업**이다:

```text
MG24 (/dev/ttyS1) ── z2m ──→ mosquitto :1883 ──→ domoticz :8081
                     라디오        브로커            UI·DB·자동화
                   (벤더 제공)   (벤더 제공)         (우리 ipk)
```

셋 다 이미 있거나 나왔다. **z2m을 내리지 마라** — 내리면 Zigbee가 사라진다.

> **이 리포는 Z4D를 쓰지 않는다** (RAIL 10). z2m이 라디오를 계속 쥐고, 분기는 없다.
> 근거는 `docs/ECOSYSTEM-PORTFOLIO.md` §6 배너와 `NEXT.md`「RAIL 10 결정」.

### 6.3 설치면

`/opt`는 **p7(`/dev/mmcblk0p7`, ext4 rw)**이고 **OTA가 건드리지 않는다.** rootfs는 ro + A/B라
설치면이 아니다. `/home`·`/var`도 같은 p7이다. 여유는 5.2G/5.7G.

---

## 6.4 domoticz ↔ z2m 연결 ✅ — 표준 경로를 세운다

RAIL 10이 고른 경로다. domoticz는 라디오를 안 물고 **MQTT로 받는다**.

> 🚫 **먼저 알아야 할 것 — 이 절이 만드는 상태는 셋 다 패키지 밖이다.**
> 공장 초기화·재설치로 **사라지고**, `.ipk`를 다시 깔아도 복원되지 않는다
> (`smhub/pack-ipk.sh`에 postinst가 없다).
>
> | 무엇 | 어디 | 소유자 |
> |---|---|---|
> | `homeassistant.enabled: true` | 벤더 `configuration.yaml` | **없음 — 손수정** |
> | `Preferences.WebLocalNetworks` | `domoticz.db` | **없음 — 손수정** |
> | `Hardware` 행 (MQTT Auto Discovery) | `domoticz.db` | **없음 — 손수정** |
> | `WebLocalNetworks`에 LAN 대역 | `domoticz.db` | **없음 — 손수정** (브라우저로 UI를 쓰려면 필요) |
>
> 제품이라면 **idempotent postinst 또는 이미지 시드**가 이 셋을 소유해야 한다
> ([#8](https://github.com/junghan0611/homeagent-config/issues/8) 축). 지금은 손으로 넣은 상태임을 알고 쓴다.

### 6.4.1 z2m — HA discovery를 켠다 ⚠️ 기본이 꺼져 있다

[측정 2026-09-08] 벤더 기본값은 **`homeassistant: enabled: false`**다. 이대로면 `homeassistant/`
토픽이 **하나도 안 나오고**, domoticz는 붙어도 **아무것도 못 본다**.

⚠️ **소유자를 반드시 보존해라.** 이 파일은 z2m 프로세스(`smlight`)가 **쓴다** — 페어링하면
기기를 여기에 기록한다. `>` 리다이렉트나 `mv`로 새 파일을 만들면 소유자가 `root`가 되고,
z2m은 조인하는 순간 `EACCES: permission denied`로 **죽는다**(실제로 밟았다, 2026-09-08).
그래서 **제자리 편집(`sed -i`)** 을 쓴다:

```sh
C=/opt/zigbee2mqtt/data/configuration.yaml
sudo cp -a "$C" "$C.bak-$(date +%Y%m%d%H%M%S)"       # cp -a 라 백업은 소유자를 보존한다
sudo sed -i '/^homeassistant:/,/^[a-z]/ s/^  enabled: false/  enabled: true/' "$C"
ls -l "$C"                               # smlight:smlight 인지 확인 ← 이 줄을 건너뛰지 마라
grep -A1 '^homeassistant:' "$C"          # enabled: true 인지 restart 전에 확인
sudo rc-service zigbee2mqtt restart
```

소유자가 어긋났으면 되돌린다: `sudo chown smlight:smlight "$C"`

원래 모습은 이렇고(들여쓰기 2칸, 최상위 블록):

```yaml
homeassistant:
  enabled: false      # ← true 로
```

**판정 — 셋을 본다** (`rc-status`가 아니라):

```sh
$SSH 'pgrep -f "^/opt/bin/node /opt/bin/zigbee2mqtt"'        # ① 프로세스가 살아 있나
$SSH 'ss -ltn | grep 8080'                                   # ② 프론트엔드가 듣나
$SSH "mosquitto_sub -h 127.0.0.1 -t 'homeassistant/#' -W 8 -v | head -3"   # ③ 토픽이 흐르나
```

③이 `Timed out`이면 discovery가 안 켜진 것이다. ①②가 비면 **z2m이 죽은 것이고, 그때도
`rc-status`는 `started`라고 말한다** — supervise-daemon이 재시작을 반복하기 때문이다.
로그가 사실원이다: `$SSH 'tail -20 /var/log/zigbee2mqtt.log'`

### 6.4.2 domoticz — 로컬 API 401부터 푼다 ⚠️ 이걸 먼저 안 하면 다음 절이 전부 막힌다

[측정] 새로 설치한 domoticz는 `Users` 테이블이 비어 있고, 그 상태에서 `json.htm`이 **401**을
돌려준다(`getversion`만 열려 있다). 로컬을 신뢰망으로 등록한다:

```sh
sudo rc-service domoticz stop
sudo sqlite3 /opt/domoticz/domoticz.db \
  "insert or replace into Preferences (Key,nValue,sValue) values ('WebLocalNetworks',0,'127.0.0.1;::1');"
sudo rc-service domoticz start
```

**브라우저로 UI를 쓸 거면 LAN 대역도 넣어라.** 안 넣으면 페이지는 뜨는데(HTTP 200) 그 안의
API 호출이 전부 401이라 **화면이 비어 보인다.** 위 값 대신 `'127.0.0.1;::1;192.168.0.*'`
(자기 대역으로).

**판정 — 다음 절로 넘어가기 전에 이게 200이어야 한다** (기기 안에서):

```sh
curl -s "http://127.0.0.1:8081/json.htm?type=command&param=gethardware"
```

> ⚠️ **관리자 계정은 아직 아무도 안 만들었다.** 지금 도는 이유는 "로컬은 무인증"이기 때문이다.
> 제품이라면 계정을 이미지가 소유해야 한다(같은 [#8](https://github.com/junghan0611/homeagent-config/issues/8) 축).

### 6.4.3 domoticz — MQTT Auto Discovery 하드웨어 추가

Web UI(`Setup → Hardware`)로도 되지만 API가 재현 가능하다. **기기 안에서** 친다(§6.4.2 때문):

```sh
Q="type=command&param=addhardware&htype=125&name=Zigbee2MQTT&enabled=true"
Q="$Q&address=127.0.0.1&port=1883&username=&password=&datatimeout=0&loglevel=7"
Q="$Q&Mode1=0&Mode2=0&Mode3=0&Mode4=0&Mode5=0&Mode6=0"
Q="$Q&extra=%3B%3B%3Bhomeassistant"        # = ";;;homeassistant"
curl -s "http://127.0.0.1:8081/json.htm?$Q"
```

**함정 둘 — 둘 다 조용히 실패한다. 치기 전에 읽어라.**

| 함정 | 증상 | 근거 |
|---|---|---|
| `Mode1`이 **대문자**이고 비면 거부 | `{"status":"ERR"}`만 나온다. 이유를 안 알려준다 | `main/WebServerCmds.cpp` `ValidateHardware` — MQTT 계열은 `smode1.empty()`면 `return false` |
| `extra`의 **네 번째 `;` 구획 = discovery prefix** | 하드웨어가 등록되고 브로커에 **연결까지 되는데 기기가 0개**다 | `hardware/MQTTAutoDiscover.cpp:57-76` — `Extra`를 `;`로 쪼개 `[3]`을 prefix로 쓰고, 비면 `"Auto Discovery Topic empty!"` 후 **아무것도 구독하지 않는다** |

두 번째가 특히 「가짜 초록」이다 — `ss`로 보면 domoticz가 1883에 established라 **연결은 성공으로
보인다.** **판정은 연결이 아니라 기기 수다.**

### 6.4.4 판정 ✅ — 실측 (2026-09-08, 한 유닛)

```text
MG24 (/dev/ttyS1) ── z2m 2.13.0 ──→ mosquitto :1883 ──→ domoticz 2026.3 :8081
```

```sh
curl -s "http://127.0.0.1:8081/json.htm?type=command&param=getdevices"   # 기기 수 > 0 이어야 한다
```

연결 직후 domoticz가 **브리지 엔티티 4개**를 자동 등록했다:

| 기기 | 값 |
|---|---|
| Zigbee2MQTT Bridge (Coordinator version) | **7.4.2 [GA]** |
| Zigbee2MQTT Bridge (Version) | **2.13** |
| Zigbee2MQTT Bridge (Permit join) | Off |
| Zigbee2MQTT Bridge (Restart required) | Off |

**EZSP 좌표(§2.1)가 domoticz까지 올라왔다** = 파이프가 끝까지 통했다는 뜻이다.
**단 Zigbee 기기는 0대다** — z2m `bridge/devices`에 Coordinator 자신뿐이라 올라올 게 없다.
"기기가 보인다"는 페어링 뒤에 다시 판정한다(§7).

---

## 7. 측정 ❓ — 이 레인이 실제로 답해야 하는 질문

기동이 확인되면 **여기가 목적지다.** `nproc`이 1이고 RAM이 488M인 기기에서:

```bash
ssh ... 'top -bn2 | grep -E "domoticz|Mem"; cat /proc/$(pgrep domoticz)/status | grep VmRSS'
```

답해야 할 값: **1코어가 세트 하나(30~40대)를 받는가.** 이게 works-nixos-zigbee 레인(x86 실증,
4스레드를 잠정 하한으로 적었다)에 돌려줄 값이다.

**같은 기기에서 둘을 나란히 재라.** z2m은 이미 돌고 있고 domoticz는 방금 올렸으니, 이 보드가
`Zigbee 호스트 + 플랫폼` 한 세트를 받는지가 한 번에 나온다:

```bash
ssh ... 'for p in $(pgrep -d" " -f "domoticz|zigbee2mqtt"); do
  echo "--- $(tr "\0" " " < /proc/$p/cmdline)"; grep -E "VmRSS|Threads" /proc/$p/status; done
  free -m | head -2; uptime'
```

이 값이 `docs/ECOSYSTEM-PORTFOLIO.md` §6.2가 x86에서만 갖고 있던 대조를 **제품 폼으로** 옮긴다.

### 7.1 실측 — 제품 폼 유휴치 (2026-09-08)

**[측정]** SMHub Nano, OS `1.0.2`, riscv64, **`nproc` 1 / MemTotal 488M**. 리부트 후 279초,
**페어링 기기 0대**, 두 스택 동시 가동.

| | `VmRSS` | Threads | CPU(279초 누적) |
|---|---|---|---|
| **domoticz 2026.3** (UI·DB·자동화) | **23.6 MB** | 18 | **1.46 s** — 0.5% |
| **zigbee2mqtt 2.13.0** (Node, 라디오) | **93.0 MB** | 11 | **33.4 s** — 12% |
| 시스템 | used 224M / **available 263M** | | load 0.29 |

읽는 법:

- **domoticz는 싸다.** 23.6 MB / CPU 0.5%. x86 §6.2의 A′(35.0 MB, Z4D 비활성)와 같은 자리이고
  제품 폼에서 오히려 작다. **부담은 domoticz가 아니다.**
- **이 스냅샷에서 비싼 쪽은 Zigbee 호스트다** — VmRSS 3.9배, 누적 CPU 23배. x86 Z4D 값
  (`EP §6.2`)은 **다른 아키텍처·다른 플러그인·다른 조건**이라 방향의 참고이지 **동일 workload의
  재현이 아니다.**
- **`EP §6.2`의 빈칸이 채워진다.** `domoticz + Z2M` 행이 미측정이었다 → **116.6 MB**. 단 이건
  **두 프로세스 VmRSS의 산술합**이라 공유 페이지가 중복 계상될 수 있다.
- **여유는 있다.** available 263M / 488M. 두 스택을 얹고도 절반이 남는다.

**⚠️ 이건 유휴치다.** 페어링 0대에서 z2m이 이미 CPU 12%를 쓴다. 30~40대에서 어떻게 되는지가
이 레인이 답해야 할 값이고, **아직 안 쟀다.** 그때까지 "1코어가 세트를 받는다"고 말하지 않는다.

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
| domoticz가 브로커에 붙었는데 기기 0개 | `extra`의 4번째 구획(discovery prefix)이 비었다 | §6.4.2 — **연결은 가짜 초록** |
| `addhardware`가 `{"status":"ERR"}`만 | `Mode1`(대문자)이 비었다 | §6.4.2 |
| `homeassistant/` 토픽이 없다 | z2m 기본값이 `enabled: false` | §6.4.1 |
| z2m이 `EACCES ... configuration.yaml`로 죽는다 | 설정 파일 소유자가 `root`로 바뀌었다 | §6.4.1 — `chown smlight:smlight`. **`rc-status`는 그때도 `started`** |
| domoticz 페이지는 뜨는데 화면이 빈다 | LAN이 신뢰망에 없어 API가 401 | §6.4.2 |
| `json.htm`이 전부 401 | 초기 domoticz는 `Users`가 비어 있다 | §6.4.3 |
| `reboot`를 보냈는데 안 내려간다 | ssh 세션과 함께 죽었다 | `nohup sh -c "sleep 2; reboot"` 후 **:22가 닫히는지 확인** |
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
