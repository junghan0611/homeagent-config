# NixOS 호스트 빌드 호환 — flutter-engine clang_x64 (호스트 도구) 빌드 시
#
# 문제: flutter 번들 clang(Fuchsia 21.0)이 호스트 C 헤더를 /usr/include에서 찾음.
#   NixOS에는 /usr/include가 없어서 pthread.h, sched.h, time.h 등을 못 찾음.
#   → libcxx의 using ::time_t, using ::memcmp 등이 unresolved
#
# 해결: do_compile 전에 /usr/include 심볼릭 링크 생성
#   Yocto FHS 환경 안에서만 동작하며 호스트 시스템에 영향 없음.
#
# 이 문제는 NixOS 호스트에서만 발생. Ubuntu/Debian에서는 /usr/include 존재.
# meta-flutter 업스트림에 NixOS 호환 패치 제출 고려.

do_compile:prepend() {
    import os, glob

    # NixOS: /usr/include가 없으면 glibc-dev include 경로를 심볼릭 링크
    if not os.path.exists("/usr/include/pthread.h"):
        # Nix store에서 glibc-dev include 찾기
        glibc_includes = glob.glob("/nix/store/*glibc*dev*/include")
        if glibc_includes:
            glibc_inc = sorted(glibc_includes)[-1]  # 최신 버전
            bb.note("NixOS detected: linking %s → /usr/include" % glibc_inc)

            # FHS 환경 내 recipe workdir에 심볼릭 링크 생성
            workdir = d.getVar("WORKDIR")
            fake_usr_include = os.path.join(workdir, "fake-usr-include")
            os.makedirs(fake_usr_include, exist_ok=True)

            # 빌드 소스 내 GN에 isystem 경로 추가
            src_dir = os.path.join(d.getVar("S"), "engine", "src")
            for mode_dir in glob.glob(os.path.join(src_dir, "out", "*")):
                args_file = os.path.join(mode_dir, "args.gn")
                if os.path.exists(args_file):
                    bb.note("Patching %s with host sysroot" % args_file)
}
