#!/usr/bin/env bash
#
# bundle-backend.sh — Go + Node.js + matterjs-server를 arm64 배포 번들로 패키징
#
# 출력: dist/homeagent-bundle-arm64/
#   ├── homeagent                  # Go 정적 바이너리
#   ├── ui/                        # Lit 프론트엔드 빌드
#   ├── node/                      # Node.js arm64 바이너리
#   ├── matterjs-server/           # matter-server npm 패키지
#   ├── aliases.json               # 디바이스 별칭
#   ├── start.sh                   # 원커맨드 시작 스크립트
#   └── .env                       # 환경변수 템플릿
#
# 사용법:
#   ./scripts/bundle-backend.sh              # 전체 빌드
#   ./scripts/bundle-backend.sh --skip-go    # Go 빌드 생략 (이미 있을 때)
#   ./scripts/bundle-backend.sh --skip-node  # Node.js 다운로드 생략
#
# 요구사항:
#   - Go 1.22+ (go 명령)
#   - Node.js + npm (matterjs-server 설치용)
#   - curl, tar
#
# 대상 플랫폼:
#   - RPi5 (Yocto aarch64) — systemd 서비스 대신 직접 실행할 때
#   - Android (RK3576 arm64) — Flutter 앱이 프로세스로 실행
#   - 어떤 arm64 Linux든 동작
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$PROJECT_DIR/dist/homeagent-bundle-arm64"

# Node.js LTS 버전 (arm64 리눅스)
NODE_VERSION="${NODE_VERSION:-20.18.2}"
NODE_TARBALL="node-v${NODE_VERSION}-linux-arm64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"

# matter-server npm 버전
MATTER_SERVER_VERSION="${MATTER_SERVER_VERSION:-0.3.5}"

# Go 버전 태그
GO_VERSION_TAG="${GO_VERSION_TAG:-$(git -C "$PROJECT_DIR" describe --tags --always 2>/dev/null || echo dev)}"

# 플래그 파싱
SKIP_GO=false
SKIP_NODE=false
SKIP_UI=false
SKIP_MATTER=false
for arg in "$@"; do
    case "$arg" in
        --skip-go)     SKIP_GO=true ;;
        --skip-node)   SKIP_NODE=true ;;
        --skip-ui)     SKIP_UI=true ;;
        --skip-matter) SKIP_MATTER=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-go] [--skip-node] [--skip-ui] [--skip-matter]"
            exit 0
            ;;
    esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[bundle]${NC} $1"; }
warn() { echo -e "${YELLOW}[bundle]${NC} $1"; }

# 클린 시작
log "번들 디렉토리: $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# ─── 1. Go 바이너리 ───────────────────────────────────────
if [ "$SKIP_GO" = false ]; then
    log "Go arm64 정적 빌드..."
    cd "$PROJECT_DIR/go"
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
        go build -ldflags="-s -w -X main.version=${GO_VERSION_TAG}" \
        -o "$BUNDLE_DIR/homeagent" ./cmd/homeagent/
    log "Go 바이너리: $(ls -lh "$BUNDLE_DIR/homeagent" | awk '{print $5}')"
else
    warn "Go 빌드 생략"
fi

# ─── 2. UI 빌드 ───────────────────────────────────────────
if [ "$SKIP_UI" = false ]; then
    log "Lit UI 빌드..."
    cd "$PROJECT_DIR/ui"
    npm install --prefer-offline 2>/dev/null || npm install
    npx vite build --outDir "$BUNDLE_DIR/ui"
    log "UI: $(du -sh "$BUNDLE_DIR/ui" | awk '{print $1}')"
else
    warn "UI 빌드 생략"
fi

# ─── 3. Node.js arm64 바이너리 ─────────────────────────────
if [ "$SKIP_NODE" = false ]; then
    log "Node.js v${NODE_VERSION} arm64 다운로드..."
    CACHE_DIR="$PROJECT_DIR/dist/.cache"
    mkdir -p "$CACHE_DIR"

    if [ ! -f "$CACHE_DIR/$NODE_TARBALL" ]; then
        curl -fSL "$NODE_URL" -o "$CACHE_DIR/$NODE_TARBALL"
    else
        log "캐시 사용: $NODE_TARBALL"
    fi

    # node 바이너리만 추출 (전체 SDK 불필요)
    mkdir -p "$BUNDLE_DIR/node"
    tar -xf "$CACHE_DIR/$NODE_TARBALL" \
        --strip-components=1 \
        -C "$BUNDLE_DIR/node" \
        "node-v${NODE_VERSION}-linux-arm64/bin/node"

    # npm도 필요 (matterjs-server 의존성 검증용, 선택)
    # 프로덕션에서는 node 바이너리만으로 충분
    log "Node.js: $(ls -lh "$BUNDLE_DIR/node/bin/node" | awk '{print $5}')"
else
    warn "Node.js 다운로드 생략"
fi

# ─── 4. matterjs-server ───────────────────────────────────
if [ "$SKIP_MATTER" = false ]; then
    log "matterjs-server v${MATTER_SERVER_VERSION} 설치..."
    mkdir -p "$BUNDLE_DIR/matterjs-server"

    # npm으로 프로덕션 의존성만 설치
    cd "$BUNDLE_DIR/matterjs-server"
    npm init -y --silent >/dev/null 2>&1
    npm install "matter-server@${MATTER_SERVER_VERSION}" --omit=dev  2>&1 | tail -3

    # 엔트리포인트 확인
    ENTRY="$BUNDLE_DIR/matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js"
    if [ -f "$ENTRY" ]; then
        log "matterjs-server: $(du -sh "$BUNDLE_DIR/matterjs-server" | awk '{print $1}')"
    else
        warn "엔트리포인트 없음! 경로 확인 필요: $ENTRY"
        find "$BUNDLE_DIR/matterjs-server/node_modules/matter-server/" -name "*.js" | head -10
    fi
else
    warn "matterjs-server 설치 생략"
fi

# ─── 5. 설정 파일 ─────────────────────────────────────────
log "설정 파일 복사..."
cp "$PROJECT_DIR/aliases.json" "$BUNDLE_DIR/"

# 환경변수 템플릿
cat > "$BUNDLE_DIR/.env" << 'EOF'
# HomeAgent Bundle 환경변수
# 실제 배포 시 수정

# Go HomeAgent
HOMEAGENT_HTTP_ADDR=:8080
HOMEAGENT_WS_URL=ws://localhost:5580/ws
HOMEAGENT_UI_DIR=./ui
HOMEAGENT_ALIASES_FILE=./aliases.json

# matterjs-server
MATTER_STORAGE_PATH=./data/matter
MATTER_WS_PORT=5580
MATTER_LOG_LEVEL=info

# LLM (OpenRouter)
OPENROUTER_API_KEY=

# WiFi (Matter 커미셔닝용)
HOMEAGENT_WIFI_SSID=
HOMEAGENT_WIFI_PASSWORD=

# Thread (OTBR에서 자동 취득, 수동 설정 시)
# HOMEAGENT_THREAD_DATASET=
EOF

# ─── 6. 시작 스크립트 ─────────────────────────────────────
cat > "$BUNDLE_DIR/start.sh" << 'STARTEOF'
#!/usr/bin/env bash
#
# HomeAgent Bundle — 원커맨드 시작
# Go(homeagent) + Node.js(matterjs-server) 동시 실행
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# 환경변수 로드
[ -f .env ] && set -a && source .env && set +a

# 데이터 디렉토리
mkdir -p "${MATTER_STORAGE_PATH:-./data/matter}"

NODE_BIN="./node/bin/node"
MATTER_ENTRY="./matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js"

log() { echo "[homeagent] $1"; }

# matterjs-server 시작 (백그라운드)
log "matterjs-server 시작 (port ${MATTER_WS_PORT:-5580})..."
"$NODE_BIN" "$MATTER_ENTRY" \
    --storage-path "${MATTER_STORAGE_PATH:-./data/matter}" \
    --port "${MATTER_WS_PORT:-5580}" &
MATTER_PID=$!

# matterjs-server 준비 대기
sleep 3

# Go HomeAgent 시작 (포그라운드)
log "homeagent 시작..."
./homeagent &
HA_PID=$!

# 종료 핸들러
cleanup() {
    log "종료 중..."
    kill "$HA_PID" 2>/dev/null || true
    kill "$MATTER_PID" 2>/dev/null || true
    wait "$HA_PID" 2>/dev/null || true
    wait "$MATTER_PID" 2>/dev/null || true
    log "종료 완료"
}
trap cleanup EXIT INT TERM

# 둘 다 살아있는지 감시
while kill -0 "$HA_PID" 2>/dev/null && kill -0 "$MATTER_PID" 2>/dev/null; do
    sleep 5
done

log "프로세스 종료 감지"
STARTEOF
chmod +x "$BUNDLE_DIR/start.sh"

# ─── 결과 요약 ─────────────────────────────────────────────
log ""
log "=== 번들 완성 ==="
echo ""
du -sh "$BUNDLE_DIR"/* 2>/dev/null | sort -rh
echo ""
log "총 크기: $(du -sh "$BUNDLE_DIR" | awk '{print $1}')"
echo ""
log "실행: cd dist/homeagent-bundle-arm64 && ./start.sh"
log "또는 Flutter 앱에서 프로세스로 실행"
