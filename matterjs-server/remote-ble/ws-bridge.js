/**
 * WS Bridge — Flutter BLE relay WebSocket 서버
 *
 * matterjs-server 시작 전에 로드하여:
 * 1. RemoteBle를 ServiceBundle에 등록
 * 2. Flutter BLE relay 연결을 받을 WS 엔드포인트 제공
 *
 * 사용: node --import ./remote-ble/ws-bridge.js MatterServer.js
 * 또는: start.sh에서 wrapper로 실행
 */
import { WebSocketServer } from "ws";
import { Ble } from "@matter/protocol";
import { Environment } from "@matter/general";
import { Logger } from "@matter/general";

// install.js를 import하면 ServiceBundle에 등록됨
import "./install.js";

const logger = Logger.get("BleWsBridge");
const BLE_WS_PORT = parseInt(process.env.BLE_WS_PORT || "5581");

let bleWss;

/**
 * BLE relay WS 서버 시작
 * Flutter가 이 포트에 연결하여 BLE 바이트를 중계
 */
export function startBleWsServer() {
  bleWss = new WebSocketServer({ port: BLE_WS_PORT });
  logger.info(`BLE relay WS server listening on port ${BLE_WS_PORT}`);

  bleWss.on("connection", (ws) => {
    logger.info("Flutter BLE relay connected");

    // Environment에서 Ble 인스턴스 가져오기
    // ServiceBundle이 deploy된 후에만 동작
    try {
      const env = Environment.default;
      if (env.has(Ble)) {
        const ble = env.get(Ble);
        if (typeof ble.setFlutterConnection === "function") {
          ble.setFlutterConnection(ws);
          logger.info("Flutter WS connected to RemoteBle");
        }
      } else {
        logger.warn("Ble not yet registered in environment — Flutter connected too early?");
        // 재시도: 1초 후
        setTimeout(() => {
          try {
            const ble = env.get(Ble);
            if (typeof ble.setFlutterConnection === "function") {
              ble.setFlutterConnection(ws);
              logger.info("Flutter WS connected to RemoteBle (retry)");
            }
          } catch (e) {
            logger.error("Failed to connect Flutter WS to RemoteBle:", e);
          }
        }, 1000);
      }
    } catch (e) {
      logger.error("Error connecting Flutter WS:", e);
    }

    ws.on("close", () => {
      logger.info("Flutter BLE relay disconnected");
    });
  });

  return bleWss;
}

// 자동 시작
startBleWsServer();
