import { LitElement, html, css, nothing } from "lit";
import { customElement, state } from "lit/decorators.js";
import {
  type DeviceState,
  type HubEvent,
  getDevices,
  sendCommand,
  subscribeEvents,
} from "./api.js";
import "./commission-dialog.js";

/** Device type → emoji icon */
function deviceIcon(type: string): string {
  switch (type) {
    case "on_off_plug":
      return "🔌";
    case "contact_sensor":
      return "🚪";
    case "dimmable_light":
    case "on_off_light":
    case "color_temp_light":
      return "💡";
    case "thermostat":
      return "🌡️";
    default:
      return "📟";
  }
}

/** Human-readable state text */
function stateText(dev: DeviceState): string {
  switch (dev.type) {
    case "contact_sensor":
      return dev.state["contact"] === true ? "열림" : "닫힘";
    case "on_off_plug":
    case "on_off_light":
    case "dimmable_light":
    case "color_temp_light":
      return dev.state["on"] === true ? "켜짐" : "꺼짐";
    case "thermostat":
      return `${dev.state["temperature"] ?? "--"}°C`;
    default:
      return dev.available ? "온라인" : "오프라인";
  }
}

/** Is this device toggleable (on/off)? */
function isToggleable(type: string): boolean {
  return [
    "on_off_plug",
    "on_off_light",
    "dimmable_light",
    "color_temp_light",
  ].includes(type);
}

@customElement("wallpad-app")
export class WallpadApp extends LitElement {
  @state() private devices: DeviceState[] = [];
  @state() private commissionOpen = false;
  @state() private darkMode = true;
  @state() private connected = false;
  @state() private errorMsg = "";

  private eventSource?: EventSource;
  private sseRetryCount = 0;

  static styles = css`
    :host {
      /* Dark theme (default) */
      --wp-bg: #0f1219;
      --wp-surface: #1a1f2e;
      --wp-surface-hover: #242a3d;
      --wp-primary: #03a9f4;
      --wp-primary-glow: rgba(3, 169, 244, 0.2);
      --wp-success: #4caf50;
      --wp-danger: #ef5350;
      --wp-text: #e8eaed;
      --wp-text-dim: #8b95a5;
      --wp-border: #2a3040;
      --wp-on: #4caf50;
      --wp-off: #5a6070;
      --wp-sensor-open: #ff9800;
      --wp-sensor-closed: #4caf50;

      display: block;
      width: 1024px;
      height: 600px;
      background: var(--wp-bg);
      color: var(--wp-text);
      font-family: "Noto Sans KR", system-ui, -apple-system, sans-serif;
      overflow: hidden;
      user-select: none;
      -webkit-user-select: none;
    }

    :host(.light) {
      --wp-bg: #f0f2f5;
      --wp-surface: #ffffff;
      --wp-surface-hover: #e8eaed;
      --wp-primary: #0288d1;
      --wp-primary-glow: rgba(2, 136, 209, 0.15);
      --wp-success: #388e3c;
      --wp-danger: #d32f2f;
      --wp-text: #1a1a2e;
      --wp-text-dim: #6b7280;
      --wp-border: #d1d5db;
      --wp-on: #388e3c;
      --wp-off: #9ca3af;
      --wp-sensor-open: #e65100;
      --wp-sensor-closed: #388e3c;
    }

    .container {
      display: flex;
      flex-direction: column;
      height: 100%;
      padding: 16px 24px;
      gap: 16px;
    }

    /* Header */
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-shrink: 0;
    }

    .header h1 {
      font-size: 24px;
      font-weight: 700;
      letter-spacing: -0.5px;
    }

    .header-actions {
      display: flex;
      gap: 12px;
      align-items: center;
    }

    .btn-icon {
      width: 48px;
      height: 48px;
      border-radius: 12px;
      border: 1px solid var(--wp-border);
      background: var(--wp-surface);
      color: var(--wp-text);
      font-size: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      transition: background 0.15s;
    }
    .btn-icon:hover {
      background: var(--wp-surface-hover);
    }
    .btn-icon:active {
      transform: scale(0.95);
    }

    /* Device grid: 3 columns × 2 rows */
    .grid {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      grid-template-rows: repeat(2, 1fr);
      gap: 16px;
      flex: 1;
      min-height: 0;
    }

    /* Device card */
    .device-card {
      background: var(--wp-surface);
      border: 1px solid var(--wp-border);
      border-radius: 16px;
      padding: 20px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      transition: background 0.15s, border-color 0.15s;
      cursor: default;
    }
    .device-card.toggleable {
      cursor: pointer;
    }
    .device-card.toggleable:hover {
      background: var(--wp-surface-hover);
    }
    .device-card.toggleable:active {
      transform: scale(0.98);
    }
    .device-card.is-on {
      border-color: var(--wp-primary);
      box-shadow: 0 0 20px var(--wp-primary-glow);
    }

    .card-top {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
    }

    .device-icon {
      font-size: 36px;
      line-height: 1;
    }

    /* Toggle indicator */
    .toggle-indicator {
      width: 52px;
      height: 28px;
      border-radius: 14px;
      background: var(--wp-off);
      position: relative;
      transition: background 0.25s;
      flex-shrink: 0;
    }
    .toggle-indicator.on {
      background: var(--wp-on);
    }
    .toggle-indicator::after {
      content: "";
      position: absolute;
      top: 3px;
      left: 3px;
      width: 22px;
      height: 22px;
      border-radius: 50%;
      background: var(--wp-text);
      transition: transform 0.25s;
    }
    .toggle-indicator.on::after {
      transform: translateX(24px);
    }

    /* Sensor status dot */
    .sensor-dot {
      width: 14px;
      height: 14px;
      border-radius: 50%;
      background: var(--wp-sensor-closed);
      transition: background 0.3s;
    }
    .sensor-dot.open {
      background: var(--wp-sensor-open);
      box-shadow: 0 0 8px var(--wp-sensor-open);
    }

    .card-bottom {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .device-name {
      font-size: 18px;
      font-weight: 600;
      line-height: 1.3;
    }

    .device-room {
      font-size: 13px;
      color: var(--wp-text-dim);
    }

    .device-state {
      font-size: 14px;
      color: var(--wp-text-dim);
      margin-top: 2px;
    }

    .device-unavailable {
      opacity: 0.4;
    }

    /* Empty slot */
    .empty-slot {
      border: 2px dashed var(--wp-border);
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--wp-text-dim);
      font-size: 14px;
    }

    /* Status bar */
    .status-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 13px;
      color: var(--wp-text-dim);
      flex-shrink: 0;
    }

    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--wp-success);
      display: inline-block;
      margin-right: 6px;
    }
    .status-dot.disconnected {
      background: var(--wp-danger);
    }
  `;

  connectedCallback() {
    super.connectedCallback();
    this.loadDevices();
    this.connectSSE();
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.eventSource?.close();
    this.eventSource = undefined;
  }

  private async loadDevices() {
    try {
      this.devices = await getDevices();
      this.connected = true;
      this.errorMsg = "";
    } catch (e) {
      console.error("[wallpad] load devices:", e);
      this.connected = false;
      this.errorMsg = "서버 연결 실패";
    }
  }

  private connectSSE() {
    this.eventSource?.close();
    this.eventSource = undefined;

    // Exponential backoff: 3s, 6s, 12s, max 30s
    const delay = Math.min(3000 * Math.pow(2, this.sseRetryCount), 30000);

    this.eventSource = subscribeEvents(
      (evt: HubEvent) => {
        this.sseRetryCount = 0;
        this.connected = true;
        this.errorMsg = "";
        this.handleEvent(evt);
      },
      () => {
        this.connected = false;
        this.eventSource?.close();
        this.eventSource = undefined;
        this.sseRetryCount++;
        if (this.sseRetryCount > 10) {
          this.errorMsg = "서버 연결 끊김 — 새로고침하세요";
          console.error("[wallpad] SSE: too many retries, stopping");
          return;
        }
        this.errorMsg = `재연결 중... (${this.sseRetryCount}/10)`;
        console.warn(`[wallpad] SSE disconnected, retry #${this.sseRetryCount} in ${delay}ms`);
        setTimeout(() => this.connectSSE(), delay);
      },
    );
  }

  private handleEvent(evt: HubEvent) {
    if (evt.type === "snapshot" && (evt as any).devices) {
      this.devices = [...(evt as any).devices];
      return;
    }

    if (evt.type === "device_state") {
      this.devices = this.devices.map((d) => {
        if (d.node_id !== evt.device_id) return d;
        const updated = { ...d, state: { ...d.state } };
        if (evt.key) {
          // Map Matter paths to keys
          const key =
            evt.key === "1/69/0"
              ? "contact"
              : evt.key === "1/6/0"
                ? "on"
                : evt.key;
          updated.state[key] = evt.value;
        }
        return updated;
      });
    }

    if (evt.type === "device_added") {
      this.loadDevices();
    }

    if (evt.type === "commission_error") {
      this.errorMsg = `페어링 실패: ${evt.value}`;
      // 5초 후 에러 메시지 자동 제거
      setTimeout(() => {
        if (this.errorMsg.startsWith("페어링")) this.errorMsg = "";
      }, 5000);
    }
  }

  private async toggleDevice(dev: DeviceState) {
    if (!isToggleable(dev.type) || !dev.available) return;

    const isOn = dev.state["on"] === true;
    try {
      await sendCommand(dev.node_id, isOn ? "off" : "on");
    } catch (e) {
      console.error("[wallpad] command failed:", e);
    }
  }

  private toggleTheme() {
    this.darkMode = !this.darkMode;
    if (this.darkMode) {
      this.classList.remove("light");
    } else {
      this.classList.add("light");
    }
  }

  private renderDeviceCard(dev: DeviceState) {
    const isOn = dev.state["on"] === true;
    const toggle = isToggleable(dev.type);
    const isSensor = dev.type === "contact_sensor";
    const contactOpen = dev.state["contact"] === true;

    return html`
      <div
        class="device-card
          ${toggle ? "toggleable" : ""}
          ${toggle && isOn ? "is-on" : ""}
          ${!dev.available ? "device-unavailable" : ""}"
        @click=${() => toggle && this.toggleDevice(dev)}
      >
        <div class="card-top">
          <span class="device-icon">${deviceIcon(dev.type)}</span>
          ${toggle
            ? html`<div class="toggle-indicator ${isOn ? "on" : ""}"></div>`
            : nothing}
          ${isSensor
            ? html`<div
                class="sensor-dot ${contactOpen ? "open" : ""}"
              ></div>`
            : nothing}
        </div>
        <div class="card-bottom">
          <div class="device-name">${dev.name}</div>
          ${dev.room
            ? html`<div class="device-room">${dev.room}</div>`
            : nothing}
          <div class="device-state">${stateText(dev)}</div>
        </div>
      </div>
    `;
  }

  render() {
    // Fill grid to 6 slots
    const maxSlots = 6;
    const filledDevices = this.devices.slice(0, maxSlots);
    const emptySlots = maxSlots - filledDevices.length;

    return html`
      <div class="container">
        <div class="header">
          <h1>🏠 HomeAgent</h1>
          <div class="header-actions">
            <button
              class="btn-icon"
              @click=${() => this.toggleTheme()}
              title="테마 전환"
            >
              ${this.darkMode ? "🌙" : "☀️"}
            </button>
            <button
              class="btn-icon"
              @click=${() => (this.commissionOpen = true)}
              title="디바이스 추가"
            >
              ➕
            </button>
          </div>
        </div>

        <div class="grid">
          ${filledDevices.map((d) => this.renderDeviceCard(d))}
          ${Array.from(
            { length: emptySlots },
            () => html`<div class="empty-slot">빈 슬롯</div>`,
          )}
        </div>

        <div class="status-bar">
          <span>
            <span
              class="status-dot ${this.connected ? "" : "disconnected"}"
            ></span>
            ${this.connected
              ? `${this.devices.length}개 디바이스`
              : this.errorMsg || "서버 연결 중..."}
          </span>
          <span>1024 × 600</span>
        </div>
      </div>

      <ha-commission-dialog
        .open=${this.commissionOpen}
        @close=${() => (this.commissionOpen = false)}
        @commissioned=${() => (this.commissionOpen = false)}
      ></ha-commission-dialog>
    `;
  }
}
