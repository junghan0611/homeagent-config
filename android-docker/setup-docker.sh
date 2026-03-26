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
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
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
    "$SCRIPT_DIR/images/matter-server-8.1.2-arm64.tar.gz" \
    "$SCRIPT_DIR/docker-android.sh" \
    "$SCRIPT_DIR/docker-compose.yml"; do
    [ -f "$f" ] || err "파일 없음: $f"
done
# OTBR 바이너리 (네이티브 빌드) — 필수
[ -f "$PROJECT_DIR/dist/otbr-arm64/otbr-agent" ] || err "OTBR 바이너리 없음. run.sh otbr-build 필요"
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
log "Docker 이미지 push (python-matter-server)..."
adb push "$SCRIPT_DIR/images/matter-server-8.1.2-arm64.tar.gz" "$REMOTE/" 2>&1 | tail -1
log "Docker 이미지 OK (OTBR은 네이티브 빌드 — Docker 이미지 불필요)"

# ─── 5. 스크립트 + compose push ───
log "스크립트 push..."
adb push "$SCRIPT_DIR/docker-android.sh" "$REMOTE/" 2>&1 | tail -1
adb push "$SCRIPT_DIR/docker-compose.yml" "$REMOTE/" 2>&1 | tail -1
adb shell "chmod 755 $REMOTE/docker-android.sh $REMOTE/docker/*"
log "스크립트 OK"

# ─── 6. OTBR 네이티브 바이너리 push ───
if [ -f "$PROJECT_DIR/dist/otbr-arm64/otbr-agent" ]; then
    log "OTBR 바이너리 push..."
    adb shell "mkdir -p $REMOTE/otbr $REMOTE/otbr-data"
    adb push "$PROJECT_DIR/dist/otbr-arm64/otbr-agent" "$REMOTE/otbr/" 2>&1 | tail -1
    adb push "$PROJECT_DIR/dist/otbr-arm64/ot-ctl" "$REMOTE/otbr/" 2>&1 | tail -1
    adb shell "chmod 755 $REMOTE/otbr/otbr-agent $REMOTE/otbr/ot-ctl"
    log "OTBR 바이너리 OK"
else
    log "WARNING: OTBR 바이너리 없음 ($PROJECT_DIR/dist/otbr-arm64/). run.sh otbr-build 필요"
fi

# ─── 7. Go 바이너리 + UI + aliases push ───
if [ -f "$PROJECT_DIR/dist/homeagent-android-arm64" ]; then
    log "Go 바이너리 push..."
    adb push "$PROJECT_DIR/dist/homeagent-android-arm64" "$REMOTE/homeagent" 2>&1 | tail -1
    adb shell "chmod 755 $REMOTE/homeagent"
else
    log "WARNING: Go 바이너리 없음 ($PROJECT_DIR/dist/homeagent-android-arm64)"
fi

if [ -d "$PROJECT_DIR/ui/dist" ]; then
    log "UI push..."
    adb shell "mkdir -p $REMOTE/ui"
    (cd "$PROJECT_DIR/ui" && tar czf /tmp/ha-ui-dist.tar.gz dist/)
    adb push /tmp/ha-ui-dist.tar.gz "$REMOTE/ui/dist.tar.gz" 2>&1 | tail -1
    adb shell "cd $REMOTE/ui && tar xzf dist.tar.gz && rm dist.tar.gz"
    rm -f /tmp/ha-ui-dist.tar.gz
fi

if [ -f "$PROJECT_DIR/aliases.json" ]; then
    adb push "$PROJECT_DIR/aliases.json" "$REMOTE/" 2>&1 | tail -1
fi
log "Go + UI + aliases OK"

# ─── 7. _start.sh 생성 (Go + APK — PC에서 생성, 보드에서 실행) ───
log "Go 시작 스크립트 생성..."

# LLM API 키 수집 (PC의 ~/.env.local에서)
_LLM_KEY="" _LLM_ENDPOINT="" _LLM_MODEL=""
if [ -f "$HOME/.env.local" ]; then
    for _envname in HOMEAGENT_LLM_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY; do
        _LLM_KEY=$(grep -m1 "^\(export \)\?${_envname}=" "$HOME/.env.local" 2>/dev/null | sed 's/^export //' | cut -d= -f2- || true)
        [ -n "$_LLM_KEY" ] && break
    done
    _LLM_ENDPOINT=$(grep -m1 "^\(export \)\?HOMEAGENT_LLM_ENDPOINT=" "$HOME/.env.local" 2>/dev/null | sed 's/^export //' | cut -d= -f2- || true)
    _LLM_MODEL=$(grep -m1 "^\(export \)\?HOMEAGENT_LLM_MODEL=" "$HOME/.env.local" 2>/dev/null | sed 's/^export //' | cut -d= -f2- || true)
fi
_LLM_ENDPOINT="${_LLM_ENDPOINT:-https://api.deepseek.com/v1}"
_LLM_MODEL="${_LLM_MODEL:-deepseek-chat}"

adb shell "cat > $REMOTE/_start.sh" << STARTEOF
#!/system/bin/sh
export HOME=$REMOTE

# WiFi 설정 복사 (SELinux 우회)
cp /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml $REMOTE/WifiConfigStore.xml 2>/dev/null
chmod 644 $REMOTE/WifiConfigStore.xml 2>/dev/null

# DNS
echo "nameserver 192.168.0.1
nameserver 8.8.8.8" > $REMOTE/resolv.conf
mount --bind $REMOTE/resolv.conf /system/etc/resolv.conf 2>/dev/null

# Go homeagent
setsid sh -c "SSL_CERT_DIR=/system/etc/security/cacerts \\
HOMEAGENT_HTTP_ADDR=:8080 \\
HOMEAGENT_MATTER_WS=ws://localhost:5580 \\
HOMEAGENT_UI_DIR=$REMOTE/ui/dist \\
HOMEAGENT_ALIASES_FILE=$REMOTE/aliases.json \\
HOMEAGENT_OTBR_REST=http://localhost:8081 \\
HOMEAGENT_LLM_ENDPOINT=$_LLM_ENDPOINT \\
HOMEAGENT_LLM_MODEL=$_LLM_MODEL \\
${_LLM_KEY:+HOMEAGENT_LLM_API_KEY=$_LLM_KEY} \\
$REMOTE/homeagent serve" \\
    > /run/homeagent.log 2>&1 &
sleep 3

# APK
APK_PKG="com.homeagent.app"
APK_ACTIVITY="com.homeagent.homeagent.MainActivity"
for i in \$(seq 1 10); do
    if pm path \$APK_PKG > /dev/null 2>&1; then
        am force-stop \$APK_PKG 2>/dev/null
        sleep 1
        am start -n \$APK_PKG/\$APK_ACTIVITY > /dev/null 2>&1
        echo "APK started"
        break
    fi
    sleep 2
done
echo "started"
STARTEOF
adb shell "chmod 755 $REMOTE/_start.sh"
log "_start.sh OK"

# ─── 8. LLM API 키 (.env) push ───
if [ -f "$HOME/.env.local" ]; then
    # .env.local에서 LLM 관련 키만 추출
    grep -E "^(export )?(HOMEAGENT_LLM_|DEEPSEEK_|OPENROUTER_)" "$HOME/.env.local" 2>/dev/null \
        | sed 's/^export //' > /tmp/ha-env-tmp
    if [ -s /tmp/ha-env-tmp ]; then
        adb push /tmp/ha-env-tmp "$REMOTE/.env" 2>&1 | tail -1
        log "LLM .env push OK"
    fi
    rm -f /tmp/ha-env-tmp
fi

# ─── 8. APK install (있으면) ───
APK_PATH="$PROJECT_DIR/flutter/build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    log "APK install..."
    adb install -r "$APK_PATH" 2>&1 | tail -1
fi

# ─── 9. 개발 도구 push (있으면) ───
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
log "  /data/local/tmp/docker-android.sh all     # 전체 스택 원커맨드"
log ""
log "개별 명령:"
log "  docker-android.sh start      # Docker Engine"
log "  docker-android.sh load       # 이미지 로드"
log "  docker-android.sh up         # 컨테이너 시작"
log "  docker-android.sh go-start   # Go 서버"
log "  docker-android.sh apk        # APK 시작"
log "  docker-android.sh status     # 상태 확인"
