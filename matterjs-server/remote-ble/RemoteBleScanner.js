/**
 * RemoteBleScanner — Scanner 인터페이스 구현
 *
 * Flutter가 BLE 스캔 결과를 WS로 전달하면,
 * matter.js의 ControllerCommissioner가 discriminator로 디바이스를 찾는다.
 *
 * 참고: @matter/nodejs-ble의 BleScanner.js (190줄)
 */
import { ChannelType, Logger, Seconds, Time, createPromise } from "@matter/general";
import { BtpCodec } from "@matter/protocol";

const logger = Logger.get("RemoteBleScanner");

export class RemoteBleScanner {
  type = ChannelType.BLE;

  /** @type {Map<string, {deviceData: object, hasAdditionalData: boolean}>} */
  #discoveredDevices = new Map();

  /** @type {Map<string, {resolver: Function, timer?: any}>} */
  #waiters = new Map();

  /** @type {WebSocket|null} */
  #flutterWs = null;

  setFlutterConnection(ws) {
    this.#flutterWs = ws;
  }

  /**
   * Flutter에서 BLE 광고 데이터 수신 시 호출
   * @param {string} address - peripheral address
   * @param {Uint8Array} serviceData - Matter BLE service data (FFF6)
   */
  handleDeviceDiscovered(address, serviceData) {
    try {
      const { discriminator, vendorId, productId, hasAdditionalAdvertisementData } =
        BtpCodec.decodeBleAdvertisementServiceData(serviceData);

      const deviceData = {
        deviceIdentifier: address,
        D: discriminator,
        SD: (discriminator >> 8) & 0x0f,
        VP: `${vendorId}+${productId}`,
        CM: 1, // commissioning mode
        addresses: [{ type: "ble", peripheralAddress: address }],
      };

      const existing = this.#discoveredDevices.has(address);
      logger.info(`${existing ? "Re-" : ""}Discovered BLE device ${address} disc=${discriminator}`);

      this.#discoveredDevices.set(address, {
        deviceData,
        hasAdditionalData: hasAdditionalAdvertisementData,
      });

      // waiter 매칭
      const queryKey = this.#findMatchingQuery(deviceData);
      if (queryKey) {
        this.#finishWaiter(queryKey, true);
      }
    } catch (error) {
      logger.debug(`Ignoring device ${address}: ${error}`);
    }
  }

  /**
   * getDiscoveredDevice — RemoteBleCentralInterface.openChannel()에서 호출
   */
  getDiscoveredDevice(address) {
    const device = this.#discoveredDevices.get(address);
    if (!device) {
      throw new Error(`No device found for address ${address}`);
    }
    return device;
  }

  // --- Scanner interface ---

  async findOperationalDevice() {
    // BLE에서 operational device 검색은 미지원
    return undefined;
  }

  getDiscoveredOperationalDevice() {
    return undefined;
  }

  async findCommissionableDevices(identifier, timeout = Seconds(10), ignoreExistingRecords = false) {
    if (ignoreExistingRecords) {
      for (const [addr] of this.#getMatchingDevices(identifier)) {
        this.#discoveredDevices.delete(addr);
      }
    }

    let matched = this.#getMatchingDevices(identifier);
    if (matched.length === 0) {
      // Flutter에 스캔 시작 요청
      this.#sendToFlutter({ cmd: "ble_scan_start" });

      const queryKey = this.#buildQueryKey(identifier);
      await this.#registerWaiter(queryKey, timeout);

      matched = this.#getMatchingDevices(identifier);
      this.#sendToFlutter({ cmd: "ble_scan_stop" });
    }

    return matched.map(([, { deviceData }]) => deviceData);
  }

  async findCommissionableDevicesContinuously(identifier, callback, timeout, cancelSignal) {
    const discovered = new Set();
    const endTime = timeout ? Date.now() + timeout : undefined;
    const queryKey = this.#buildQueryKey(identifier);

    this.#sendToFlutter({ cmd: "ble_scan_start" });

    let canceled = false;
    cancelSignal?.then(() => {
      canceled = true;
      this.#finishWaiter(queryKey, true);
    });

    while (!canceled) {
      for (const [, { deviceData }] of this.#getMatchingDevices(identifier)) {
        if (!discovered.has(deviceData.deviceIdentifier)) {
          discovered.add(deviceData.deviceIdentifier);
          callback(deviceData);
        }
      }

      if (endTime && Date.now() >= endTime) break;

      const remaining = endTime ? endTime - Date.now() : undefined;
      if (remaining !== undefined && remaining <= 0) break;

      await this.#registerWaiter(queryKey, remaining);
    }

    this.#sendToFlutter({ cmd: "ble_scan_stop" });
    return this.#getMatchingDevices(identifier).map(([, { deviceData }]) => deviceData);
  }

  getDiscoveredCommissionableDevices(identifier) {
    return this.#getMatchingDevices(identifier).map(([, { deviceData }]) => deviceData);
  }

  cancelCommissionableDeviceDiscovery(identifier, resolvePromise = true) {
    const queryKey = this.#buildQueryKey(identifier);
    this.#finishWaiter(queryKey, resolvePromise);
  }

  async close() {
    for (const [key] of this.#waiters) {
      this.#finishWaiter(key, true);
    }
    this.#discoveredDevices.clear();
  }

  // --- 내부 헬퍼 ---

  #sendToFlutter(msg) {
    if (this.#flutterWs?.readyState === 1) {
      this.#flutterWs.send(JSON.stringify(msg));
    }
  }

  async #registerWaiter(queryKey, timeout) {
    const { promise, resolver } = createPromise();
    let timer;
    if (timeout) {
      timer = Time.getTimer("BLE scan timeout", timeout, () => {
        this.#finishWaiter(queryKey, true);
      }).start();
    }
    this.#waiters.set(queryKey, { resolver, timer });
    await promise;
  }

  #finishWaiter(queryKey, resolve) {
    const waiter = this.#waiters.get(queryKey);
    if (!waiter) return;
    waiter.timer?.stop();
    if (resolve) waiter.resolver();
    this.#waiters.delete(queryKey);
  }

  #getMatchingDevices(identifier) {
    const entries = [...this.#discoveredDevices.entries()];
    if ("longDiscriminator" in identifier) {
      return entries.filter(([, { deviceData }]) => deviceData.D === identifier.longDiscriminator);
    }
    if ("shortDiscriminator" in identifier) {
      return entries.filter(([, { deviceData }]) => deviceData.SD === identifier.shortDiscriminator);
    }
    if ("vendorId" in identifier) {
      return entries.filter(([, { deviceData }]) =>
        deviceData.VP?.startsWith(`${identifier.vendorId}`)
      );
    }
    // 기본: 모든 commissioning mode 디바이스
    return entries.filter(([, { deviceData }]) => deviceData.CM === 1 || deviceData.CM === 2);
  }

  #findMatchingQuery(deviceData) {
    const longKey = `D:${deviceData.D}`;
    if (this.#waiters.has(longKey)) return longKey;
    const shortKey = `SD:${deviceData.SD}`;
    if (this.#waiters.has(shortKey)) return shortKey;
    if (this.#waiters.has("*")) return "*";
    return undefined;
  }

  #buildQueryKey(identifier) {
    if ("longDiscriminator" in identifier) return `D:${identifier.longDiscriminator}`;
    if ("shortDiscriminator" in identifier) return `SD:${identifier.shortDiscriminator}`;
    if ("vendorId" in identifier) return `V:${identifier.vendorId}`;
    if ("instanceId" in identifier) return `I:${identifier.instanceId}`;
    return "*";
  }
}
