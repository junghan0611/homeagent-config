/**
 * RemoteBle — Ble 추상 클래스의 WS relay 구현
 *
 * NodeJsBle 대체. noble 대신 Flutter가 BLE 작업을 수행하고
 * WebSocket으로 바이트를 중계.
 */
import { Ble } from "@matter/protocol";
import { RemoteBleCentralInterface } from "./RemoteBleCentralInterface.js";
import { RemoteBleScanner } from "./RemoteBleScanner.js";

export class RemoteBle extends Ble {
  #scanner;
  #centralInterface;
  #options;

  constructor(options) {
    super();
    this.#options = options;
  }

  get scanner() {
    if (!this.#scanner) {
      this.#scanner = new RemoteBleScanner();
    }
    return this.#scanner;
  }

  get centralInterface() {
    if (!this.#centralInterface) {
      this.#centralInterface = new RemoteBleCentralInterface(this.scanner);
    }
    return this.#centralInterface;
  }

  get peripheralInterface() {
    // peripheral (advertise) 기능은 controller에서 불필요
    throw new Error("RemoteBle does not support peripheral mode");
  }

  /**
   * Flutter WS 연결을 받아 scanner와 transport에 주입
   */
  setFlutterConnection(ws) {
    this.scanner.setFlutterConnection(ws);
    if (this.#centralInterface) {
      this.#centralInterface.setFlutterConnection(ws);
    }
  }
}
