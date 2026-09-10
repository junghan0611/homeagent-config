# `smhub/` — SMHub Nano 제품 폼에 우리 페이로드를 얹는 레인

**`bsp/`와 다른 종류의 디렉터리다.** `bsp/`는 **이미지를 만든다**(Milk-V Duo S, 우리가 부트체인부터
소유). 여기는 **이미지를 만들지 않는다** — SMHub Nano는 벤더 OS(SMHUB, RAUC A/B, rootfs ro)가
돌고, 우리가 소유할 수 있는 건 **p7의 설치면과 `.ipk` 하나**다. 그래서 이 트리의 산출물은
이미지가 아니라 **그 벤더 rootfs에서 무수정으로 도는 riscv64 바이너리**다.

- **처음 왔다면 → [`RUNBOOK.md`](RUNBOOK.md)** — 새 기기 개봉부터 **Zigbee 데이터가 마스터로
  나가기까지**의 순서. 이 README는 **왜**를, RUNBOOK은 **무엇을 어떤 순서로**를 말한다.
- ⚠️ **2026-09-10 배치 변경.** 보드는 **Z2M + mosquitto(LAN)** 만 쥐고, **domoticz는 마스터**에서
  MQTT-AD로 붙는다. 아래 domoticz `.ipk` 레인은 **닫힌 이식성 증명**이다 — 벤더 rootfs에서
  우리 riscv64 바이너리가 무수정으로 돈다는 것을 보였고, 그 목적을 다했다. 현재 운용 경로가
  아니다(`NEXT.md` RAIL 16).
- 판(왜/무엇을): [#10](https://github.com/junghan0611/homeagent-config/issues/10)
- 기기 사실(SSOT): `docs/SMHUB.md` — §4.1(플랫폼·ABI) · §3.7(설치면) · §3.6(SSH)
- 현재 좌표: `NEXT.md` RAIL 16·18 (RAIL 9는 닫힌 이식성 증명)

---

## 왜 버전이 두 방향인가

| 축 | 방향 | 이유 |
|---|---|---|
| **domoticz** | **최신 `2026.3`** | Buildroot 핀 `2024.4`는 2년 넘게 뒤졌다. 2026.3이 실증 레인이 도는 버전이고 여기서 검증·배포한 버전이다 |
| **툴체인** | **기기와 동일 (`2026.02`)** | 기기 glibc **2.42**. 최신 master(2.44)로 빌드하면 심볼이 없어 **아예 시작하지 않는다** |

기기 실측(2026-09-08, SSH): Buildroot `2026.02-1281-g9407f694e5` · 커널 6.18.17-patch21 ·
**glibc 2.42** · **GCC 15.2.0** · `libstdc++.so.6.0.34` · **Python 3.14.6** · ISA `rv64imafdc` ·
**`nproc` 1** · MemTotal 488M.

벤더 rev의 `-1281`은 upstream에 없는 벤더 커밋이라 bit-identical 재현은 불가하다. **재현 가능한
base는 upstream 태그 `2026.02`**이고(glibc `2.42-51-gcbf39c2`, GCC 15.2.0 선택 가능),
`setup.sh`가 **커밋 SHA와 glibc 핀 둘 다** 검증하고 어긋나면 멈춘다.

> 2026-09-08까지 이 검사는 **glibc만** 봤고, 기존 트리는 HEAD가 밀려 있어도 통과했다.
> (교차검토에서 잡힘.) 지금은 `refs/tags/2026.02^{commit}`과 대조한다 — annotated tag이므로
> `^{commit}` 피일링이 필요하고, 그걸 빼면 tag object SHA와 비교해 **맞는 트리를 틀렸다고 읽는다.**

## 쓰는 법

```bash
./smhub/setup.sh          # upstream Buildroot 2026.02 클론 + glibc 핀 검증 (한 번)
./smhub/build.sh          # 주입 → make domoticz
./smhub/build.sh menuconfig   # 아무 make 타깃도 됨
```

- 트리는 `smhub/sdk/`(gitignore). **SSOT는 이 디렉터리**이고 `build.sh`가 매번 주입한다:
  `smhub/buildroot/<cfg>_defconfig` → `configs/`, `smhub/package/domoticz/` → `package/domoticz/`.
  양쪽에 두면 드리프트 — `bsp/`와 같은 규칙이다.
- **make는 컨테이너에서 돈다**(`milkvtech/milkv-duo:latest`, UID 매칭). Buildroot가
  `/usr/bin/file`을 하드코딩으로 요구하는데 NixOS엔 없다. Buildroot는 자기 크로스 툴체인을 직접
  굽기 때문에 **컨테이너는 POSIX 호스트일 뿐 산출물 ABI에 기여하지 않는다.**
  - ⚠️ **호스트와 컨테이너를 섞어 굽지 마라.** 호스트에서 만든 `output/build/buildroot-config/conf`는
    nix 로더에 링크돼 컨테이너에서 `Error 127`로 죽는다. 섞였으면 `rm -rf smhub/sdk/output`.
  - ⚠️ **컨테이너는 프로세스보다 오래 산다.** `docker run`을 띄운 셸/감독 프로세스를 죽여도
    컨테이너는 계속 굽는다 — 그 상태로 다시 시작하면 **두 make가 같은 트리를 쓴다.** 재시작 전
    확인: `docker ps --filter ancestor=milkvtech/milkv-duo:latest`, 남아 있으면 `docker kill <id>`.
- **중단은 안전하고, 이어굽기가 기본이다.** Buildroot는 `output/build/*/.stamp_*`로 단계를 기억하므로
  랩탑이 잠들거나 빌드를 죽여도 `./smhub/build.sh` 한 번이면 **그 패키지부터** 이어간다
  (지운 것만 다시 굽는다 — `rm -rf output`은 툴체인부터 전부 다시라는 뜻).
- **첫 빌드 소요 (실측, 랩탑 16코어, 2026-09-08)**: 호스트 툴 8개 ≈13분 → 크로스 툴체인
  (binutils 2.44 · GCC 15.2 · **glibc 2.42**) + boost 1.83 + python3 ≈1시간 →
  **domoticz 다운로드 3시간 28분** → **컴파일+설치 2분 55초**.
  ⚠️ **다운로드가 컴파일의 70배다** — git+서브모듈이라 그렇고, `dl/`에 캐시되므로 두 번째부터는
  안 문다. 호스트를 옮길 땐 `smhub/sdk/dl/`을 같이 옮겨라. 진행 확인은
  `tail smhub/sdk/output/build/build-time.log` 또는 `ls smhub/sdk/output/build/*/.stamp_built | wc -l`.

## 조달 판정 — 무엇을 싣고 무엇을 안 싣나

벤더 opkg 피드(`pkg.smlight.tech/v1`)에 **domoticz는 없다**(45 stanza / 17 앱, 라이브러리 패키지 0).
그래서 우리가 만든다. rootfs가 이미 지불한 것은 다시 싣지 않는다:

**실측으로 확정됐다 (2026-09-08, `pack-ipk.sh`가 기기에 직접 물어 도출)**: NEEDED 폐포 15개 중
**기기가 13개를 제공**하고 **동봉은 2개뿐**이다.

| rootfs에 있다 (쓴다) — 13 | 동봉 — 2 | 정적 내장 |
|---|---|---|
| `libsqlite3.so.0` · `libssl.so.3` · `libcrypto.so.3` · `libcurl.so.4` · **`libmosquitto.so.1`** · `libz.so.1` · `libresolv.so.2` · `libm.so.6` · `libatomic.so.1` · `libc.so.6` · `libstdc++.so.6` · `libgcc_s.so.1` · `ld-linux-riscv64-lp64d.so.1` | **`libboost_thread.so.1.83.0`** · **`liblua.so.5.3.6`** | jsoncpp · minizip · jwt-cpp · libwebem |

- **boost는 4개가 아니라 1개였다.** 계획은 `thread`·`system`·`date_time`·`atomic` 넷을 동봉하는
  것이었는데, 실제 링크된 것은 **`thread` 하나**다. ipk가 그만큼 가볍다.
- **`libsqlite3`**: 기기 실물은 `libsqlite3.so.3.53.2`(1.0.2에서 3.51.2→3.53.2로 올랐다)지만
  **`.so.0` 심링크가 있어** soname이 맞는다 → 동봉 불필요.
- **`libpython3.14.so.1.0`은 NEEDED에 없다 — dlopen이기 때문이다.** NEEDED에 없다고 Python이
  꺼진 게 아니라는 뜻이고, 판정은 configure 로그로 한다(`RUNBOOK.md` §4.4). 플러그인을 안 쓰면
  CPython 인스턴스가 아예 안 떠서 **비용이 0**이다.

- **서브모듈은 회피 불가**: 태그 타르볼의 `extern/` 5개는 빈 디렉터리이고, `extern/libwebem`은
  `add_subdirectory`가 **무조건** 걸려 있다 → `SITE_METHOD=git` + `GIT_SUBMODULES=YES`.
  **새 Buildroot 패키지는 0개.**
  - ⚠️ **태그 이름은 provenance가 아니다.** 리비전을 태그의 gitlink가 고정하는 건 맞지만, 그
    사실이 아티팩트에 기록되지는 않는다. 그래서 `pack-ipk.sh`가 Buildroot가 만든 소스
    타르볼의 **sha256을 매니페스트에 `domoticz-src`로 적는다** — 그 해시가 superproject와
    서브모듈 5개를 함께 덮는 실제 영수증이다.
- **boost는 정적이 안 된다**: Buildroot boost는 `link=shared` 고정이고, 전역 `BR2_STATIC_LIBS`는
  domoticz가 금지한다 → boost는 `.ipk`에 동봉한다(실측 결과 `thread` 하나면 된다).

## 설치 계약 (§3.7 패턴 (a))

- 설치면은 **p7 하나**: `/opt/domoticz`(= 이 defconfig의 `CMAKE_INSTALL_PREFIX`). rootfs(ro, A/B)는
  설치면이 아니다 — 다음 OTA에 사라진다.
- 서비스는 **OpenRC**(`/etc/init.d`, overlay upper가 p7), ipk 메타는 벤더 형식을 모사:
  `Architecture: riscv64`, `Required-OS-Version`.
- `PATH`에 `/opt/bin`이 없다 → **절대경로로 실행**한다(벤더도 그렇게 한다).
- ⚠️ **8080은 비어 있지 않다**: 벤더 z2m 프론트엔드가 쓴다(실측 2026-09-08,
  `/opt/bin/node /opt/bin/zigbee2mqtt`) → 우리는 **8081**.
- ⚠️ **라디오는 하나다**: `/dev/ttyS1`(MG24)을 z2m이 점유 중이다. 우리 패키지는 그 포트를
  건드리지 않는다. **Zigbee는 MQTT로 받는다**(RAIL 10) — z2m을 내리지 않는다.

## 판정 규칙 — 「가짜 초록」을 먼저 의심한다

이 라인은 성공 출력이 생존의 증거가 아닌 자리를 반복해서 만났다(`usb_dl`의 100% 거짓 완료,
`rc-status`의 started, `ssh-keygen -A` 뒤 되돌아온 0바이트 키). 그래서 판정은 항상 사실원으로 한다:

| 주장 | 사실원 |
|---|---|
| "빌드됐다" | `readelf -d`의 NEEDED 목록 + `file`의 ISA/인터프리터 |
| "설치됐다" | `opkg list-installed` + 실제 파일 경로 |
| "돌고 있다" | `pgrep`/`ss`, **`rc-status` 아님** |
| "쓸 수 있다" | 위젯이 아니라 **값**. (전례: Z4D는 `0702`/`0b04`를 읽고도 버리고 On/Off로 등록했다 — 화면은 정상으로 보인다) |
| "연결됐다" | 연결이 아니라 **기기 수**. domoticz는 브로커에 붙고도 구독을 안 할 수 있다(`RUNBOOK.md` §6.4.3) |
