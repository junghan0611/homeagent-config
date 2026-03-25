# Android Docker 배포 — python-matter-server + OTBR

## 목표

RK3576 Android 15에서 Docker로 python-matter-server + OTBR 실행.
RPi5와 같은 docker-compose.yml 기반 통합 배포.

## 구조

```
android-docker/
├── README.md                    # 이 문서
├── docker-android.sh            # Docker Engine 기동 (chroot 방식)
├── docker-compose.yml           # 서비스 정의 (matter-server + OTBR)
├── docker-compose.android.yml   # Android override (dbus 제거, OTBR 조건부)
├── .env.android                 # Android 환경변수
├── push-to-board.sh             # PC → 보드 전송 스크립트
└── images/                      # Docker 이미지 tar (gitignore)
    ├── matter-server-arm64.tar
    └── otbr-arm64.tar
```

## 전제조건

- AOSP 이미지: 패치 006 (Docker 커널) + 007 (/dev/run tmpfs, /dev/cg_devices)
- Docker Engine static binary: `/tmp/docker-29.3.0.tgz`
- Docker Compose: `/tmp/docker-compose-linux-aarch64`

## 단계

1. Docker 이미지 준비 (PC에서 pull → save)
2. push-to-board.sh로 보드에 전송
3. docker-android.sh start → Docker Engine 기동
4. docker load → 이미지 로드
5. docker-compose up -d → 서비스 시작

## 참고

- 가이드: kyungdong-rockchip/docs/DOCKER-ON-ANDROID-GUIDE.md
- PM 문서: llmlog/20260324T131721 (Docker 기반 Matter+OTBR 배포 전환)
