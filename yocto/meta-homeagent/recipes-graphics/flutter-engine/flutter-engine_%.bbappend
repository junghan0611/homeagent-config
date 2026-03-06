# flutter-engine은 자체 번들 clang(Fuchsia clang 21.0) + 자체 libcxx를 사용.
# meta-clang이 CXXFLAGS에 -stdlib=libc++를 넣으면 Yocto sysroot의 libc++ 18.x 헤더가
# flutter의 libcxx 21.0 헤더와 충돌하여 "unresolved using declaration" 에러 발생.
#
# 해결: flutter-engine 빌드 시 -stdlib=libc++ 제거
# flutter의 custom toolchain BUILD.gn이 자체 libcxx 경로를 직접 관리함.

CXXFLAGS:remove = "-stdlib=libc++"
BUILD_CXXFLAGS:remove = "-stdlib=libc++"
