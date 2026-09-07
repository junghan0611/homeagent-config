# `smhub/` — SMHub Nano 제품 폼에 우리 페이로드를 얹는 레인

**`bsp/`와 다른 종류의 디렉터리다.** `bsp/`는 **이미지를 만든다**(Milk-V Duo S, 우리가 부트체인부터
소유). 여기는 **이미지를 만들지 않는다** — SMHub Nano는 벤더 OS(SMHUB, RAUC A/B, rootfs ro)가
돌고, 우리가 소유할 수 있는 건 **p7의 설치면과 `.ipk` 하나**다. 그래서 이 트리의 산출물은
이미지가 아니라 **그 벤더 rootfs에서 무수정으로 도는 riscv64 바이너리**다.

- 판(왜/무엇을): [#10](https://github.com/junghan0611/homeagent-config/issues/10)
- 기기 사실(SSOT): `docs/SMHUB.md` — §4.1(플랫폼·ABI) · §3.7(설치면) · §3.6(SSH)
- 현재 좌표: `NEXT.md` RAIL 9

---

## 왜 버전이 두 방향인가

| 축 | 방향 | 이유 |
|---|---|---|
| **domoticz** | **최신 `2026.3`** | Buildroot 핀 `2024.4`는 Z4D 게이트(≥2025.1, 권장 2025.2)를 못 넘는다. 실증 레인이 도는 버전과도 같다 |
| **툴체인** | **기기와 동일 (`2026.02`)** | 기기 glibc **2.42**. 최신 master(2.44)로 빌드하면 심볼이 없어 **아예 시작하지 않는다** |

기기 실측(2026-09-07, SSH): Buildroot `2026.02-1281-g9407f694e5` · 커널 6.18.17-patch21 ·
**glibc 2.42** · **GCC 15.2.0** · `libstdc++.so.6.0.34` · **Python 3.14.6** · ISA `rv64imafdc` ·
**`nproc` 1** · MemTotal 488M.

벤더 rev의 `-1281`은 upstream에 없는 벤더 커밋이라 bit-identical 재현은 불가하다. **재현 가능한
base는 upstream 태그 `2026.02`**이고(glibc `2.42-51-gcbf39c2`, GCC 15.2.0 선택 가능),
`setup.sh`가 그 핀을 **검증하고 아니면 멈춘다**.

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

## 조달 판정 — 무엇을 싣고 무엇을 안 싣나

벤더 opkg 피드(`pkg.smlight.tech/v1`)에 **domoticz는 없다**(45 stanza / 17 앱, 라이브러리 패키지 0).
그래서 우리가 만든다. rootfs가 이미 지불한 것은 다시 싣지 않는다:

| rootfs에 있다 (쓴다) | 없다 (우리가 해결) |
|---|---|
| `libcurl.so.4` · `libsqlite3.so.3.51.2` · `libssl.so.3` · **`libmosquitto.so.1`** · `libjsoncpp.so.26` · `libz` · **`libpython3.14.so.1.0`** · `libstdc++.so.6.0.34` | **boost**(동봉) · **lua 5.3** · **minizip**(정적 내장) · jwt-cpp·libwebem·jsoncpp(정적 내장) |

- **서브모듈은 회피 불가**: 태그 타르볼의 `extern/` 5개는 빈 디렉터리이고, `extern/libwebem`은
  `add_subdirectory`가 **무조건** 걸려 있다 → `SITE_METHOD=git` + `GIT_SUBMODULES=YES`.
  리비전은 태그의 gitlink가 고정하므로 재현성이 유지된다. **새 Buildroot 패키지는 0개.**
- **boost는 정적이 안 된다**: Buildroot boost는 `link=shared` 고정이고, 전역 `BR2_STATIC_LIBS`는
  domoticz가 금지한다 → boost 4개(`thread`·`system`·`date_time`·`atomic`)는 `.ipk`에 동봉.

## 설치 계약 (§3.7 패턴 (a))

- 설치면은 **p7 하나**: `/opt/domoticz`(= 이 defconfig의 `CMAKE_INSTALL_PREFIX`). rootfs(ro, A/B)는
  설치면이 아니다 — 다음 OTA에 사라진다.
- 서비스는 **OpenRC**(`/etc/init.d`, overlay upper가 p7), ipk 메타는 벤더 형식을 모사:
  `Architecture: riscv64`, `Required-OS-Version`.
- `PATH`에 `/opt/bin`이 없다 → **절대경로로 실행**한다(벤더도 그렇게 한다).

## 판정 규칙 — 「가짜 초록」을 먼저 의심한다

이 라인은 성공 출력이 생존의 증거가 아닌 자리를 반복해서 만났다(`usb_dl`의 100% 거짓 완료,
`rc-status`의 started, `ssh-keygen -A` 뒤 되돌아온 0바이트 키). 그래서 판정은 항상 사실원으로 한다:

| 주장 | 사실원 |
|---|---|
| "빌드됐다" | `readelf -d`의 NEEDED 목록 + `file`의 ISA/인터프리터 |
| "설치됐다" | `opkg list-installed` + 실제 파일 경로 |
| "돌고 있다" | `pgrep`/`ss`, **`rc-status` 아님** |
| "쓸 수 있다" | 위젯이 아니라 값 — Z4D는 `0702`/`0b04`를 읽고도 버리고 On/Off로 등록한다 |
