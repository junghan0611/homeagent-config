/**
 * RemoteBleCentralInterface — ConnectionlessTransport 구현
 *
 * noble의 NobleBleCentralInterface를 대체.
 * Flutter가 Android BLE API로 실제 BLE 작업을 수행하고,
 * WS로 바이트를 중계.
 *
 * 핵심 흐름:
 * 1. openChannel(address) → Flutter에 ble_connect 전송
 * 2. Flutter가 C1/C2 특성 발견 후 ble_connected 응답
 * 3. BtpSessionHandler가 BTP 핸드셰이크/세그멘테이션 처리
 * 4. C1 write → ble_write → Flutter → BLE device
 * 5. C2 indicate → Flutter → ble_data → BtpSessionHandler
 *
 * 참고: @matter/nodejs-ble의 NobleBleChannel.ts
 */
import {
  ChannelType,
  Logger,
  createPromise,
  Seconds,
  Time,
} from "@matter/general";
import {
  BleChannel,
  BLE_MAXIMUM_BTP_MTU,
  BTP_SUPPORTED_VERSIONS,
  BTP_MAXIMUM_WINDOW_SIZE,
  BTP_CONN_RSP_TIMEOUT,
  BtpCodec,
  BtpSessionHandler,
} from "@matter/protocol";

const logger = Logger.get("RemoteBleCentral");

/**
 * RemoteBleChannel — BleChannel의 WS relay 구현
 */
class RemoteBleChannel extends BleChannel {
  #btpSession;
  #address;
  #connected = true;

  constructor(address, btpSession) {
    super();
    this.#address = address;
    this.#btpSession = btpSession;
  }

  get connected() {
    return this.#connected;
  }

  get name() {
    return `ble://${this.#address}`;
  }

  async send(data) {
    if (!this.#connected) {
      logger.debug(`Cannot send — not connected to ${this.#address}`);
      return;
    }
    await this.#btpSession.sendMatterMessage(data);
  }

  async close() {
    await this.#btpSession.close();
    this.#connected = false;
  }

  setDisconnected() {
    this.#connected = false;
    this.#btpSession.close();
  }
}

/**
 * RemoteBleCentralInterface — ConnectionlessTransport
 */
export class RemoteBleCentralInterface {
  #scanner;
  #flutterWs = null;
  #onMatterMessageListener;
  #openChannels = new Map();
  #pendingResponses = new Map();

  constructor(scanner) {
    this.#scanner = scanner;
  }

  setFlutterConnection(ws) {
    this.#flutterWs = ws;

    ws.on("message", (raw) => {
      try {
        const msg = JSON.parse(raw.toString());
        this.#handleFlutterMessage(msg);
      } catch (e) {
        logger.error("Failed to parse Flutter message:", e);
      }
    });

    ws.on("close", () => {
      logger.info("Flutter BLE relay disconnected");
      this.#flutterWs = null;
      // 모든 열린 채널 정리
      for (const [addr, channel] of this.#openChannels) {
        channel.setDisconnected();
        this.#openChannels.delete(addr);
      }
    });
  }

  supports(type, _address) {
    return type === ChannelType.BLE;
  }

  onData(listener) {
    this.#onMatterMessageListener = listener;
    return {
      close: async () => {
        await this.close();
      },
    };
  }

  async close() {
    for (const [addr, channel] of this.#openChannels) {
      await channel.close();
      this.#sendToFlutter({ cmd: "ble_disconnect", address: addr });
    }
    this.#openChannels.clear();
  }

  /**
   * openChannel — ControllerCommissioner가 BLE 커미셔닝 시 호출
   *
   * 1. Flutter에 ble_connect 전송
   * 2. Flutter가 connect → service discovery → ble_connected 응답
   * 3. BTP 핸드셰이크
   * 4. BleChannel 반환
   */
  async openChannel(address) {
    const peripheralAddress = address.peripheralAddress;
    logger.info(`Opening BLE channel to ${peripheralAddress}`);

    if (!this.#flutterWs || this.#flutterWs.readyState !== 1) {
      throw new Error("Flutter BLE relay not connected");
    }

    if (this.#openChannels.has(peripheralAddress)) {
      throw new Error(`Already connected to ${peripheralAddress}`);
    }

    // 1. Flutter에 연결 요청
    const connectedPromise = this.#waitForResponse("ble_connected", peripheralAddress, 30000);
    this.#sendToFlutter({
      cmd: "ble_connect",
      address: peripheralAddress,
    });

    const connResp = await connectedPromise;
    const mtu = connResp.mtu || 247;
    const effectiveMtu = Math.min(mtu, BLE_MAXIMUM_BTP_MTU);
    logger.info(`Connected to ${peripheralAddress}, MTU=${effectiveMtu}`);

    // 2. BTP 핸드셰이크
    const { promise: hsPromise, resolver: hsResolver } = createPromise();

    const hsTimeout = Time.getTimer("BTP handshake timeout", BTP_CONN_RSP_TIMEOUT, () => {
      hsResolver(null);
    }).start();

    // C2 indicate 핸들러 (핸드셰이크 응답 대기)
    let hsHandler = (data) => {
      if (data[0] === 0x65 && data[1] === 0x6c && data.length === 6) {
        hsTimeout.stop();
        hsHandler = null;
        hsResolver(data);
      }
    };

    // C2 데이터 수신 등록
    const c2DataKey = `c2_${peripheralAddress}`;
    this.#pendingResponses.set(c2DataKey, (data) => {
      if (hsHandler) {
        hsHandler(data);
      }
    });

    // BTP 핸드셰이크 요청 전송
    const hsRequest = BtpCodec.encodeBtpHandshakeRequest({
      versions: BTP_SUPPORTED_VERSIONS,
      attMtu: effectiveMtu,
      clientWindowSize: BTP_MAXIMUM_WINDOW_SIZE,
    });

    this.#sendToFlutter({
      cmd: "ble_write",
      address: peripheralAddress,
      data: Array.from(new Uint8Array(hsRequest)),
    });

    const hsResponse = await hsPromise;
    if (!hsResponse) {
      this.#sendToFlutter({ cmd: "ble_disconnect", address: peripheralAddress });
      throw new Error(`BTP handshake timeout for ${peripheralAddress}`);
    }

    // 3. BTP 세션 생성
    // channel을 먼저 선언 — disconnect/message 콜백에서 참조 (TDZ 방지)
    let channel;

    const btpSession = await BtpSessionHandler.createAsCentral(
      new Uint8Array(hsResponse),
      // writeBleCallback — C1 write
      async (data) => {
        this.#sendToFlutter({
          cmd: "ble_write",
          address: peripheralAddress,
          data: Array.from(new Uint8Array(data)),
        });
      },
      // disconnectBleCallback
      async () => {
        this.#sendToFlutter({ cmd: "ble_disconnect", address: peripheralAddress });
        if (channel) {
          channel.setDisconnected();
        }
        this.#openChannels.delete(peripheralAddress);
      },
      // handleMatterMessagePayload — 조립된 Matter 메시지
      async (data) => {
        if (this.#onMatterMessageListener && channel) {
          this.#onMatterMessageListener(channel, data);
        }
      },
    );

    // C2 핸들러를 BTP 세션으로 전환
    this.#pendingResponses.set(c2DataKey, (data) => {
      btpSession.handleIncomingBleData(new Uint8Array(data));
    });

    channel = new RemoteBleChannel(peripheralAddress, btpSession);
    this.#openChannels.set(peripheralAddress, channel);

    logger.info(`BLE channel established to ${peripheralAddress}`);
    return channel;
  }

  // --- 내부 ---

  #sendToFlutter(msg) {
    if (this.#flutterWs?.readyState === 1) {
      this.#flutterWs.send(JSON.stringify(msg));
    }
  }

  #handleFlutterMessage(msg) {
    switch (msg.event) {
      case "ble_connected":
        this.#resolveResponse("ble_connected", msg.address, msg);
        break;

      case "ble_data": {
        // C2 indicate 데이터
        const handler = this.#pendingResponses.get(`c2_${msg.address}`);
        if (handler) {
          handler(new Uint8Array(msg.data));
        }
        break;
      }

      case "ble_disconnected": {
        const channel = this.#openChannels.get(msg.address);
        if (channel) {
          channel.setDisconnected();
          this.#openChannels.delete(msg.address);
        }
        this.#pendingResponses.delete(`c2_${msg.address}`);
        break;
      }

      case "ble_scan_result": {
        // 스캔 결과 → scanner로 전달
        if (msg.address && msg.serviceData) {
          this.#scanner.handleDeviceDiscovered(msg.address, new Uint8Array(msg.serviceData));
        }
        break;
      }

      default:
        logger.debug(`Unknown Flutter event: ${msg.event}`);
    }
  }

  /**
   * 특정 응답을 기다리는 Promise
   */
  #waitForResponse(eventType, address, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
      const key = `${eventType}_${address}`;
      const timer = setTimeout(() => {
        this.#pendingResponses.delete(key);
        reject(new Error(`Timeout waiting for ${eventType} from ${address}`));
      }, timeoutMs);

      this.#pendingResponses.set(key, (data) => {
        clearTimeout(timer);
        this.#pendingResponses.delete(key);
        resolve(data);
      });
    });
  }

  #resolveResponse(eventType, address, data) {
    const key = `${eventType}_${address}`;
    const handler = this.#pendingResponses.get(key);
    if (handler) {
      handler(data);
    }
  }
}
