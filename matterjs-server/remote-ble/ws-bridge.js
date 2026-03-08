/**
 * WS Bridge — Flutter BLE relay WebSocket 서버
 *
 * matterjs-server 시작 전에 로드하여:
 * 1. RemoteBle를 ServiceBundle에 등록
 * 2. Flutter BLE relay 연결을 받을 WS 엔드포인트 제공
 *
 * 사용: node --import ./remote-ble/ws-bridge.js MatterServer.js
 */
import { WebSocketServer } from "ws";
import { Ble } from "@matter/protocol";
import { Environment, Logger } from "@matter/general";

// install.js를 import하면 ServiceBundle에 등록됨
import "./install.js";

const logger = Logger.get("BleWsBridge");
const BLE_WS_PORT = parseInt(process.env.BLE_WS_PORT || "5581");

/**
 * 대기 중인 Flutter WS 연결을 저장.
 * RemoteBle가 env에 등록되기 전에 Flutter가 연결할 수 있으므로,
 * pending으로 보관 후 Ble가 준비되면 주입.
 */
let pendingFlutterWs = null;
let bleAttached = false;

function tryAttachFlutter(ws) {
  try {
    const env = Environment.default;
    if (env.has(Ble)) {
      const ble = env.get(Ble);
      if (typeof ble.setFlutterConnection === "function") {
        ble.setFlutterConnection(ws);
        bleAttached = true;
        pendingFlutterWs = null;
        logger.info("Flutter WS attached to RemoteBle");
        return true;
      }
    }
  } catch (_) {
    // env not ready yet
  }
  return false;
}

// 주기적으로 pending WS를 Ble에 연결 시도 (env 준비될 때까지)
const attachInterval = setInterval(() => {
  if (pendingFlutterWs && pendingFlutterWs.readyState === 1) {
    if (tryAttachFlutter(pendingFlutterWs)) {
      clearInterval(attachInterval);
    }
  } else if (bleAttached) {
    clearInterval(attachInterval);
  }
}, 500);

// 60초 후 포기
setTimeout(() => clearInterval(attachInterval), 60000);

const bleWss = new WebSocketServer({ port: BLE_WS_PORT });
logger.info(`BLE relay WS server listening on port ${BLE_WS_PORT}`);

bleWss.on("connection", (ws) => {
  logger.info("Flutter BLE relay connected");

  if (!tryAttachFlutter(ws)) {
    // Ble 아직 미등록 — pending으로 보관
    logger.info("Ble not ready, holding Flutter WS connection until env initialized");
    pendingFlutterWs = ws;
  }

  ws.on("close", () => {
    logger.info("Flutter BLE relay disconnected");
    if (pendingFlutterWs === ws) {
      pendingFlutterWs = null;
    }
    bleAttached = false;
  });
});
