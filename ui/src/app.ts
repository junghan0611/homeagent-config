import { LitElement, html, css } from "lit";
import { customElement, state } from "lit/decorators.js";
import { getDevices, getHomeSurface, subscribeEvents, type DeviceState, type HubEvent } from "./api.js";
import "./device-card.js";
import "./commission-dialog.js";
import "./chat-panel.js";
import "./a2ui-renderer.js";

@customElement("ha-app")
export class App extends LitElement {
  @state() private devices: DeviceState[] = [];
  @state() private connected = false;
  @state() private showCommission = false;
  @state() private lastEvent = "";
  @state() private agentMessage = "";
  @state() private homeSurface: any = null;
  @state() private llmSurface: any = null;

  private eventSource?: EventSource;
  private _surfaceTimer?: number;
  private sseRetryCount = 0;
  private eventLog: string[] = [];

  static styles = css`
    :host {
      display: block;
      min-height: 100vh;
      /* Variables inherited from styles.ts globalStyles or defined here as fallback */
      --ha-bg: #0a0e1a;
      --ha-surface: #141824;
      --ha-border: #2a2e3e;
      --ha-primary: #03a9f4;
      --ha-primary-hover: #0288d1;
      --ha-primary-glow: rgba(3, 169, 244, 0.3);
      --ha-text: #e5e7eb;
      --ha-text-muted: #9ca3af;
      --ha-text-dim: #6b7280;
      --ha-text-faint: #4b5563;
      --ha-text-secondary: #d1d5db;
      --ha-success: #4caf50;
      --ha-error: #f44336;
      --ha-white: #fff;
      background: var(--ha-bg);
      color: var(--ha-text);
      font-family: system-ui, -apple-system, "Roboto", sans-serif;
      transition: background 0.8s ease;
    }

    :host(.mood-morning)   { --ha-bg: #1a1208; --ha-surface: #241a0c; --ha-border: #4a3510; --ha-primary: #FF9800; }
    :host(.mood-forenoon)  { --ha-bg: #1a1808; --ha-surface: #24200c; --ha-border: #4a4510; --ha-primary: #FFC107; }
    :host(.mood-noon)      { --ha-bg: #1a1008; --ha-surface: #24180c; --ha-border: #4a2810; --ha-primary: #FF5722; }
    :host(.mood-afternoon) { --ha-bg: #081420; --ha-surface: #0c1c2c; --ha-border: #163050; --ha-primary: #03A9F4; }
    :host(.mood-evening)   { --ha-bg: #100820; --ha-surface: #180c2c; --ha-border: #2a1650; --ha-primary: #7C4DFF; }
    :host(.mood-night)     { --ha-bg: #08081a; --ha-surface: #0e0e24; --ha-border: #1a1a40; --ha-primary: #5C6BC0; }
    :host(.mood-latenight) { --ha-bg: #050508; --ha-surface: #0a0a12; --ha-border: #14141e; --ha-primary: #37474F; }

    .container { max-width: 800px; margin: 0 auto; padding: 24px 16px; }

    .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 32px; }
    .logo { display: flex; align-items: center; gap: 12px; }
    .logo-icon { width: 44px; height: 44px; background: linear-gradient(135deg, var(--ha-primary), var(--ha-success)); border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 22px; }
    .logo h1 { font-size: 22px; font-weight: 700; margin: 0; }
    .logo .sub { font-size: 11px; color: var(--ha-text-dim); margin-top: 1px; }

    .status-dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; margin-right: 6px; }
    .status-dot.online { background: var(--ha-success); box-shadow: 0 0 6px rgba(76, 175, 80, 0.5); }
    .status-dot.offline { background: var(--ha-error); }
    .status { font-size: 12px; color: var(--ha-text-muted); display: flex; align-items: center; }

    .agent-bar { background: var(--ha-surface); border: 1px solid var(--ha-border); border-radius: 14px; padding: 16px 20px; margin-bottom: 24px; display: flex; align-items: center; gap: 12px; animation: slideIn 0.3s ease; }
    @keyframes slideIn { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: translateY(0); } }
    .agent-avatar { font-size: 24px; }
    .agent-text { font-size: 14px; color: var(--ha-text-secondary); line-height: 1.5; }
    .agent-text em { color: var(--ha-primary); font-style: normal; font-weight: 600; }

    .section-title { font-size: 13px; font-weight: 600; color: var(--ha-text-dim); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 16px; display: flex; align-items: center; justify-content: space-between; }
    .devices-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; margin-bottom: 32px; }

    .empty { text-align: center; padding: 60px 20px; color: var(--ha-text-dim); }
    .empty .icon { font-size: 48px; margin-bottom: 16px; }
    .empty p { margin: 8px 0; }

    .fab { background: linear-gradient(135deg, var(--ha-primary), var(--ha-primary-hover)); color: var(--ha-white); border: none; border-radius: 16px; padding: 12px 24px; font-size: 14px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 8px; transition: all 0.2s ease; box-shadow: 0 4px 14px var(--ha-primary-glow); }
    .fab:hover { transform: translateY(-1px); box-shadow: 0 6px 20px var(--ha-primary-glow); }

    .event-log { background: var(--ha-surface); border: 1px solid var(--ha-border); border-radius: 14px; padding: 16px 20px; }
    .event-log h3 { font-size: 13px; color: var(--ha-text-dim); margin: 0 0 12px; text-transform: uppercase; letter-spacing: 1px; }
    .event-item { font-family: "JetBrains Mono", "Fira Code", monospace; font-size: 12px; color: var(--ha-text-muted); padding: 4px 0; border-bottom: 1px solid var(--ha-border-subtle, rgba(255,255,255,0.03)); }
    .event-item:last-child { border-bottom: none; }
    .event-item .time { color: var(--ha-text-faint); }
    .event-item .val-true { color: var(--ha-success); }
    .event-item .val-false { color: var(--ha-error); }
  `;

  connectedCallback() {
    super.connectedCallback();
    this.loadDevices();
    this.loadHomeSurface();
    this.connectSSE();
    this._surfaceTimer = window.setInterval(() => this.loadHomeSurface(), 60_000);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.eventSource?.close();
    if (this._surfaceTimer) clearInterval(this._surfaceTimer);
  }

  private async loadHomeSurface() {
    try {
      this.homeSurface = await getHomeSurface();
      this.applyTheme(this.homeSurface?.theme);
    } catch { /* ignore */ }
  }

  private applyTheme(theme?: { accent?: string; bg?: string; mood?: string }) {
    if (!theme) return;
    const host = this.shadowRoot?.host as HTMLElement;
    if (!host) return;
    host.className = host.className.replace(/mood-\S+/g, "").trim();
    if (theme.mood) host.classList.add(`mood-${theme.mood}`);
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

  private connectSSE() {
    this.eventSource?.close();
    this.eventSource = undefined;
    const delay = Math.min(3000 * Math.pow(2, this.sseRetryCount), 30000);
    this.eventSource = subscribeEvents(
      (evt) => { this.sseRetryCount = 0; this.handleEvent(evt); },
      () => {
        this.connected = false;
        this.eventSource?.close();
        this.eventSource = undefined;
        this.sseRetryCount++;
        if (this.sseRetryCount > 10) return;
        setTimeout(() => this.connectSSE(), delay);
      }
    );
  }

  private handleEvent(evt: HubEvent) {
    this.connected = true;
    if (evt.type === "device_state") {
      this.devices = this.devices.map((d) => {
        if (d.node_id === evt.device_id && evt.key) {
          const newState = { ...d.state };
          if (evt.key === "1/69/0") newState["contact"] = evt.value;
          else if (evt.key === "1/6/0") newState["on"] = evt.value;
          else newState[evt.key] = evt.value;
          return { ...d, state: newState };
        }
        return d;
      });
      const now = new Date().toLocaleTimeString("ko-KR");
      const val = evt.value;
      const label = evt.key === "1/69/0" ? (val ? "🚪 열림" : "🔒 닫힘") : evt.key === "1/6/0" ? (val ? "🔌 켜짐" : "⭕ 꺼짐") : `${evt.key}=${val}`;
      this.eventLog = [`${now} Node ${evt.device_id}: ${label}`, ...this.eventLog.slice(0, 19)];
      this.lastEvent = label;
      this.requestUpdate();
    }
    if (evt.type === "device_added") { this.loadDevices(); this.agentMessage = `🎉 새 디바이스가 추가되었습니다! <em>Node ${evt.device_id}</em>`; }
    if (evt.type === "commission_error") { this.agentMessage = `⚠️ 페어링 실패: ${evt.value}`; }
    if (evt.type === "agent_message") {
      this.agentMessage = `🤖 ${evt.value}`;
      const chatPanel = this.shadowRoot?.querySelector("ha-chat-panel") as any;
      if (chatPanel?.addAgentMessage && evt.value) chatPanel.addAgentMessage(`🔔 ${evt.value}`);
    }
    if (evt.type === "surface_update") { this.llmSurface = evt.value; setTimeout(() => { this.llmSurface = null; }, 30_000); }
    if (evt.type === "device_state" || evt.type === "device_added") this.loadHomeSurface();
  }

  private updateAgentMessage() {
    if (this.devices.length === 0) {
      this.agentMessage = "안녕하세요! 아직 연결된 디바이스가 없습니다. <em>페어링</em>을 시작해 보세요.";
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
        <ha-a2ui-renderer .surface=${this.homeSurface}></ha-a2ui-renderer>
        ${this.llmSurface ? html`<ha-a2ui-renderer .surface=${this.llmSurface}></ha-a2ui-renderer>` : ""}
        <div class="agent-bar">
          <div class="agent-avatar">🤖</div>
          <div class="agent-text" .innerHTML=${this.agentMessage}></div>
        </div>
        <div class="section-title">
          <span>디바이스 (${this.devices.length})</span>
          <button class="fab" @click=${() => (this.showCommission = true)}>➕ 페어링</button>
        </div>
        ${this.devices.length > 0
          ? html`<div class="devices-grid">${this.devices.map((d) => html`<ha-device-card .device=${d}></ha-device-card>`)}</div>`
          : html`<div class="empty"><div class="icon">📡</div><p>연결된 디바이스가 없습니다</p><p>Matter 디바이스를 페어링해 보세요</p></div>`}
        <ha-chat-panel></ha-chat-panel>
        <br/>
        ${this.eventLog.length > 0 ? html`
          <div class="event-log">
            <h3>실시간 이벤트</h3>
            ${this.eventLog.map((e) => html`<div class="event-item">${e.includes("열림") ? html`<span class="val-true">${e}</span>` : e.includes("닫힘") ? html`<span class="val-false">${e}</span>` : e}</div>`)}
          </div>` : ""}
      </div>
      <ha-commission-dialog .open=${this.showCommission} @close=${() => (this.showCommission = false)} @commissioned=${() => this.handleCommissioned()}></ha-commission-dialog>
    `;
  }
}
