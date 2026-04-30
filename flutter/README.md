# HomeAgent Flutter Shell

이 디렉토리는 HomeAgent의 Flutter 클라이언트다. 기본 Flutter 템플릿 문서가 아니라, 프로젝트 문서는 아래를 기준으로 본다.

- Flutter 아키텍처/빌드: [`../docs/FLUTTER.md`](../docs/FLUTTER.md)
- 서버 주도 UI 전략: [`../docs/A2UI.md`](../docs/A2UI.md)
- API 명세: [`../docs/API.md`](../docs/API.md)
- 전체 문서 지도: [`../docs/README.md`](../docs/README.md)

원칙:

- Android/Linux Desktop은 native UI (`NavShell`)가 기본이다.
- RPi5 Yocto는 ivi-homescreen/WebView shell 경로를 유지한다.
- UI 상태/테마 결정은 가능하면 Go 서버 surface에서 하고, Flutter는 렌더링 계층으로 둔다.
