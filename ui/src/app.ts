import { LitElement, html, css } from "lit";
import { customElement, state } from "lit/decorators.js";
import { getDevices, subscribeEvents, type DeviceState, type HubEvent } from "./api.js";
import "./device-card.js";
import "./commission-dialog.js";

@customElement("ha-app")
export class App extends LitElement {
  @state()
  private devices: DeviceState[] = [];

  @state()
  private connected = false;

  @state()
  private showCommission = false;

  @state()
  private lastEvent = "";

  @state()
  private agentMessage = "";

  private eventSource?: EventSource;

  static styles = css`
    :host {
      display: block;
      min-height: 100vh;
      background:
        radial-gradient(1200px 900px at 15% 20%, rgba(3, 169, 244, 0.08), transparent 55%),
        radial-gradient(900px 700px at 85% 80%, rgba(76, 175, 80, 0.06), transparent 60%),
        #0a0e1a;
      color: #e5e7eb;
      font-family: system-ui, -apple-system, "Roboto", sans-serif;
    }

    .container {
      max-width: 800px;
      margin: 0 auto;
      padding: 24px 16px;
    }

    /* Header */
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 32px;
    }

    .logo {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .logo-icon {
      width: 44px;
      height: 44px;
      background: linear-gradient(135deg, #03a9f4, #4caf50);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
    }

    .logo h1 {
      font-size: 22px;
      font-weight: 700;
      margin: 0;
    }

    .logo .sub {
      font-size: 11px;
      color: #6b7280;
      margin-top: 1px;
    }

    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      display: inline-block;
      margin-right: 6px;
    }
    .status-dot.online {
      background: #4caf50;
      box-shadow: 0 0 6px rgba(76, 175, 80, 0.5);
    }
    .status-dot.offline {
      background: #f44336;
    }

    .status {
      font-size: 12px;
      color: #9ca3af;
      display: flex;
      align-items: center;
    }

    /* Agent message */
    .agent-bar {
      background: #141824;
      border: 1px solid #2a2e3e;
      border-radius: 14px;
      padding: 16px 20px;
      margin-bottom: 24px;
      display: flex;
      align-items: center;
      gap: 12px;
      animation: slideIn 0.3s ease;
    }

    @keyframes slideIn {
      from {
        opacity: 0;
        transform: translateY(-8px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    .agent-avatar {
      font-size: 24px;
    }

    .agent-text {
      font-size: 14px;
      color: #d1d5db;
      line-height: 1.5;
    }
    .agent-text em {
      color: #03a9f4;
      font-style: normal;
      font-weight: 600;
    }

    /* Devices grid */
    .section-title {
      font-size: 13px;
      font-weight: 600;
      color: #6b7280;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .devices-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
      gap: 16px;
      margin-bottom: 32px;
    }

    .empty {
      text-align: center;
      padding: 60px 20px;
      color: #6b7280;
    }
    .empty .icon {
      font-size: 48px;
      margin-bottom: 16px;
    }
    .empty p {
      margin: 8px 0;
    }

    /* Fab button */
    .fab {
      background: linear-gradient(135deg, #03a9f4, #0288d1);
      color: #fff;
      border: none;
      border-radius: 16px;
      padding: 12px 24px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 8px;
      transition: all 0.2s ease;
      box-shadow: 0 4px 14px rgba(3, 169, 244, 0.3);
    }
    .fab:hover {
      transform: translateY(-1px);
      box-shadow: 0 6px 20px rgba(3, 169, 244, 0.4);
    }

    /* Event log */
    .event-log {
      background: #141824;
      border: 1px solid #2a2e3e;
      border-radius: 14px;
      padding: 16px 20px;
    }
    .event-log h3 {
      font-size: 13px;
      color: #6b7280;
      margin: 0 0 12px;
      text-transform: uppercase;
      letter-spacing: 1px;
    }
    .event-item {
      font-family: "JetBrains Mono", "Fira Code", monospace;
      font-size: 12px;
      color: #9ca3af;
      padding: 4px 0;
      border-bottom: 1px solid rgba(255, 255, 255, 0.03);
    }
    .event-item:last-child {
      border-bottom: none;
    }
    .event-item .time {
      color: #4b5563;
    }
    .event-item .val-true {
      color: #4caf50;
    }
    .event-item .val-false {
      color: #f44336;
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
  }

  private async loadDevices() {
    try {
      this.devices = await getDevices();
      this.connected = true;
      this.updateAgentMessage();
    } catch {
      this.connected = false;
      this.agentMessage = "Hub에 연결할 수 없습니다. Go 컨트롤러가 실행 중인지 확인하세요.";
    }
  }

  private sseRetryCount = 0;

  private connectSSE() {
    // Close previous connection
    this.eventSource?.close();
    this.eventSource = undefined;

    // Backoff: 3s, 6s, 12s, max 30s
    const delay = Math.min(3000 * Math.pow(2, this.sseRetryCount), 30000);

    this.eventSource = subscribeEvents(
      (evt) => {
        this.sseRetryCount = 0; // Reset on success
        this.handleEvent(evt);
      },
      () => {
        this.connected = false;
        this.eventSource?.close();
        this.eventSource = undefined;
        this.sseRetryCount++;
        if (this.sseRetryCount > 10) {
          console.error("SSE: too many retries, stopping");
          return;
        }
        setTimeout(() => this.connectSSE(), delay);
      }
    );
  }

  private eventLog: string[] = [];

  private handleEvent(evt: HubEvent) {
    this.connected = true;

    if (evt.type === "device_state") {
      // Update device state in-place
      this.devices = this.devices.map((d) => {
        if (d.node_id === evt.device_id && evt.key) {
          const newState = { ...d.state };
          // Map Matter paths to keys
          if (evt.key === "1/69/0") {
            newState["contact"] = evt.value;
          } else {
            newState[evt.key] = evt.value;
          }
          return { ...d, state: newState };
        }
        return d;
      });

      // Log
      const now = new Date().toLocaleTimeString("ko-KR");
      const val = evt.value;
      const label =
        evt.key === "1/69/0"
          ? val
            ? "🚪 열림"
            : "🔒 닫힘"
          : `${evt.key}=${val}`;
      this.eventLog = [`${now} Node ${evt.device_id}: ${label}`, ...this.eventLog.slice(0, 19)];
      this.lastEvent = label;
      this.requestUpdate();
    }

    if (evt.type === "device_added") {
      this.loadDevices();
      this.agentMessage = `🎉 새 디바이스가 추가되었습니다! <em>Node ${evt.device_id}</em>`;
    }

    if (evt.type === "commission_error") {
      this.agentMessage = `⚠️ 페어링 실패: ${evt.value}`;
    }
  }

  private updateAgentMessage() {
    if (this.devices.length === 0) {
      this.agentMessage =
        "안녕하세요! 아직 연결된 디바이스가 없습니다. <em>페어링</em>을 시작해 보세요.";
    } else {
      const names = this.devices.map((d) => d.name || `Node ${d.node_id}`).join(", ");
      this.agentMessage = `현재 <em>${this.devices.length}개</em> 디바이스가 연결되어 있습니다: ${names}`;
    }
  }

  private handleCommissioned() {
    this.showCommission = false;
    this.agentMessage = "🔗 페어링 진행 중... 디바이스가 페어링 모드인지 확인하세요. (60~120초 소요)";
  }

  render() {
    return html`
      <div class="container">
        <!-- Header -->
        <div class="header">
          <div class="logo">
            <div class="logo-icon">🏠</div>
            <div>
              <h1>HomeAgent</h1>
              <div class="sub">Matter Hub · On-Device AI</div>
            </div>
          </div>
          <div class="status">
            <span class="status-dot ${this.connected ? "online" : "offline"}"></span>
            ${this.connected ? "온라인" : "오프라인"}
          </div>
        </div>

        <!-- Agent message bar -->
        <div class="agent-bar">
          <div class="agent-avatar">🤖</div>
          <div class="agent-text" .innerHTML=${this.agentMessage}></div>
        </div>

        <!-- Devices -->
        <div class="section-title">
          <span>디바이스 (${this.devices.length})</span>
          <button class="fab" @click=${() => (this.showCommission = true)}>
            ➕ 페어링
          </button>
        </div>

        ${this.devices.length > 0
          ? html`
              <div class="devices-grid">
                ${this.devices.map(
                  (d) => html`<ha-device-card .device=${d}></ha-device-card>`
                )}
              </div>
            `
          : html`
              <div class="empty">
                <div class="icon">📡</div>
                <p>연결된 디바이스가 없습니다</p>
                <p>Matter 디바이스를 페어링해 보세요</p>
              </div>
            `}

        <!-- Event log -->
        ${this.eventLog.length > 0
          ? html`
              <div class="event-log">
                <h3>실시간 이벤트</h3>
                ${this.eventLog.map(
                  (e) => html`
                    <div class="event-item">
                      ${e.includes("열림")
                        ? html`<span class="val-true">${e}</span>`
                        : e.includes("닫힘")
                          ? html`<span class="val-false">${e}</span>`
                          : e}
                    </div>
                  `
                )}
              </div>
            `
          : ""}
      </div>

      <!-- Commission dialog -->
      <ha-commission-dialog
        .open=${this.showCommission}
        @close=${() => (this.showCommission = false)}
        @commissioned=${() => this.handleCommissioned()}
      ></ha-commission-dialog>
    `;
  }
}
