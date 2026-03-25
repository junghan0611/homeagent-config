#!/bin/bash
# setup-docker.sh — 클린 Android 보드에 Docker 환경 원커맨드 설치
#
# 사용법 (PC에서):
#   ./setup-docker.sh
#
# 전제:
#   - adb가 PATH에 있고 보드가 연결됨
#   - 같은 폴더에 images/ 디렉토리:
#       images/docker-29.3.0.tgz
#       images/docker-compose-linux-aarch64
#       images/matter-server-arm64.tar.gz
#       images/otbr-arm64.tar.gz
#
# 결과:
#   보드에서 docker-android.sh {start|load|up} 순서로 실행하면
#   python-matter-server + OTBR 컨테이너가 뜸

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE="/data/local/tmp"

log() { echo "[setup] $*"; }
err() { echo "[setup] ERROR: $*" >&2; exit 1; }

# ─── 사전 확인 ───
log "=== Android Docker 설치 ==="

# adb 연결 확인
adb devices | grep -q "device$" || err "adb 디바이스 없음. USB 연결 확인."

# 필수 파일 확인
for f in \
    "$SCRIPT_DIR/images/docker-29.3.0.tgz" \
    "$SCRIPT_DIR/images/docker-compose-linux-aarch64" \
    "$SCRIPT_DIR/images/matter-server-arm64.tar.gz" \
    "$SCRIPT_DIR/images/otbr-arm64.tar.gz" \
    "$SCRIPT_DIR/docker-android.sh" \
    "$SCRIPT_DIR/docker-compose.yml"; do
    [ -f "$f" ] || err "파일 없음: $f"
done
log "필수 파일 확인 OK"

# ─── 1. adb root ───
log "adb root..."
adb root 2>/dev/null || true
sleep 2

# ─── 2. Docker 바이너리 push + 풀기 ───
log "Docker Engine 바이너리 push..."
adb push "$SCRIPT_DIR/images/docker-29.3.0.tgz" "$REMOTE/" 2>&1 | tail -1
adb shell "cd $REMOTE && tar xzf docker-29.3.0.tgz && rm docker-29.3.0.tgz"
log "Docker Engine 바이너리 OK"

# ─── 3. Docker Compose push ───
log "Docker Compose push..."
adb push "$SCRIPT_DIR/images/docker-compose-linux-aarch64" "$REMOTE/docker/docker-compose" 2>&1 | tail -1
adb shell "chmod 755 $REMOTE/docker/docker-compose"
log "Docker Compose OK"

# ─── 4. Docker 이미지 push ───
log "Docker 이미지 push (시간 소요)..."
adb push "$SCRIPT_DIR/images/matter-server-arm64.tar.gz" "$REMOTE/" 2>&1 | tail -1
adb push "$SCRIPT_DIR/images/otbr-arm64.tar.gz" "$REMOTE/" 2>&1 | tail -1
log "Docker 이미지 OK"

# ─── 5. 스크립트 + compose push ───
log "스크립트 push..."
adb push "$SCRIPT_DIR/docker-android.sh" "$REMOTE/" 2>&1 | tail -1
adb push "$SCRIPT_DIR/docker-compose.yml" "$REMOTE/" 2>&1 | tail -1
adb shell "chmod 755 $REMOTE/docker-android.sh"
log "스크립트 OK"

# ─── 6. 개발 도구 push (있으면) ───
if [ -f "$SCRIPT_DIR/images/tools/curl" ]; then
    log "개발 도구 push..."
    adb push "$SCRIPT_DIR/images/tools/curl" "$REMOTE/curl" 2>&1 | tail -1
    adb push "$SCRIPT_DIR/images/tools/jq" "$REMOTE/jq" 2>&1 | tail -1
    adb shell "chmod 755 $REMOTE/curl $REMOTE/jq"
fi

# ─── 7. 확인 ───
log ""
log "=== 설치 완료 ==="
log ""
log "보드 파일 구조:"
adb shell "ls -la $REMOTE/docker/ | head -15"
log ""
log "사용법 (adb shell에서):"
log "  1. /data/local/tmp/docker-android.sh start   # Docker Engine 시작"
log "  2. /data/local/tmp/docker-android.sh load    # 이미지 로드"
log "  3. /data/local/tmp/docker-android.sh up      # 서비스 시작"
log "  4. /data/local/tmp/docker-android.sh status   # 상태 확인"
log ""
log "전부 한 번에:"
log "  adb shell '/data/local/tmp/docker-android.sh start && /data/local/tmp/docker-android.sh load && /data/local/tmp/docker-android.sh up'"
