/**
 * RemoteBle — ServiceBundle 등록
 *
 * @matter/nodejs-ble의 install.ts를 대체.
 * noble 없이 Flutter BLE relay를 통해 BLE transport를 제공.
 *
 * 사용: MatterServer.js 시작 전에 import "./remote-ble/install.js"
 */
import { Environment, ServiceBundle } from "@matter/general";
import { Ble } from "@matter/protocol";
import { RemoteBle } from "./RemoteBle.js";

function remoteBleInstaller(env) {
  let installed = false;
  let instance = undefined;

  // ble.enable을 강제 활성화 — Android에 hci0 없으므로 CLI 옵션 우회
  env.vars.set("ble.enable", true);

  env.vars.use(() => {
    const shouldInstall = env.vars.boolean("ble.enable");
    if (shouldInstall === installed) return;

    if (shouldInstall) {
      instance = new RemoteBle({ environment: env });
      env.set(Ble, instance);
    } else {
      env.delete(Ble, instance);
      instance = undefined;
    }
    installed = shouldInstall;
  });
}

ServiceBundle.default.add(remoteBleInstaller);
