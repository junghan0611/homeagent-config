import { LitElement, html, css } from "lit";
import { customElement, property } from "lit/decorators.js";
import { sendCommand, type DeviceState } from "./api.js";

@customElement("ha-device-card")
export class DeviceCard extends LitElement {
  @property({ type: Object }) device!: DeviceState;

  static styles = css`
    :host { display: block; }

    .card {
      background: var(--ha-surface, #141824);
      border: 1px solid var(--ha-border, #2a2e3e);
      border-radius: var(--ha-radius-lg, 16px);
      padding: 24px;
      transition: all 0.3s ease;
      position: relative;
      overflow: hidden;
    }
    .card::before {
      content: "";
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 3px;
      background: var(--ha-primary, #03a9f4);
      transition: background 0.3s ease;
    }
    .card.on::before  { background: var(--ha-success); }
    .card.off::before { background: var(--ha-error); }
    .card.open::before  { background: var(--ha-success); }
    .card.closed::before { background: var(--ha-error); }

    .header { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
    .icon { font-size: 32px; width: 48px; height: 48px; display: flex; align-items: center; justify-content: center; border-radius: 12px; background: var(--ha-primary-dim, rgba(3, 169, 244, 0.1)); }
    .info h3 { font-size: 16px; font-weight: 600; color: var(--ha-text, #e5e7eb); margin: 0; }
    .info .type { font-size: 12px; color: var(--ha-text-muted, #9ca3af); margin-top: 2px; }

    .state-row { display: flex; align-items: center; justify-content: space-between; padding: 12px 16px; background: var(--ha-border-subtle, rgba(255, 255, 255, 0.03)); border-radius: 10px; }
    .state-left { display: flex; align-items: center; gap: 10px; }

    .state-dot { width: 12px; height: 12px; border-radius: 50%; transition: all 0.3s ease; }
    .state-dot.on, .state-dot.open   { background: var(--ha-success); box-shadow: 0 0 8px var(--ha-success-glow, rgba(76,175,80,0.5)); }
    .state-dot.off, .state-dot.closed { background: var(--ha-error); box-shadow: 0 0 8px var(--ha-error-glow, rgba(244,67,54,0.5)); }

    .state-label { font-size: 18px; font-weight: 600; }
    .state-label.on, .state-label.open   { color: var(--ha-success); }
    .state-label.off, .state-label.closed { color: var(--ha-error); }

    .toggle { position: relative; width: 56px; height: 30px; border-radius: 15px; border: none; cursor: pointer; transition: all 0.3s ease; background: var(--ha-border, #2a2e3e); padding: 0; }
    .toggle.on { background: var(--ha-success); }
    .toggle::after { content: ""; position: absolute; top: 3px; left: 3px; width: 24px; height: 24px; border-radius: 50%; background: var(--ha-white, #fff); transition: transform 0.3s ease; }
    .toggle.on::after { transform: translateX(26px); }
    .toggle:active { transform: scale(0.95); }

    .meta { margin-top: 12px; font-size: 11px; color: var(--ha-text-dim, #6b7280); }
  `;

  private get isOn(): boolean { return this.device?.state?.on === true; }
  private get isOpen(): boolean { return this.device?.state?.contact === true; }
  private get stateClass(): string {
    switch (this.device?.type) {
      case "contact_sensor": return this.isOpen ? "open" : "closed";
      case "on_off_plug": case "on_off_light": return this.isOn ? "on" : "off";
      default: return "";
    }
  }
  private get icon(): string {
    switch (this.device?.type) {
      case "contact_sensor": return this.isOpen ? "🚪" : "🔒";
      case "on_off_plug": return this.isOn ? "🔌" : "⭕";
      case "on_off_light": return this.isOn ? "💡" : "🌑";
      default: return "📡";
    }
  }
  private get stateText(): string {
    switch (this.device?.type) {
      case "contact_sensor": return this.isOpen ? "열림 (Open)" : "닫힘 (Closed)";
      case "on_off_plug": case "on_off_light": return this.isOn ? "켜짐 (ON)" : "꺼짐 (OFF)";
      default: return JSON.stringify(this.device?.state || {});
    }
  }
  private get protocol(): string {
    switch (this.device?.type) {
      case "contact_sensor": return "Matter over Thread";
      case "on_off_plug": case "on_off_light": return "Matter over WiFi";
      default: return "Matter";
    }
  }
  private get hasToggle(): boolean { return this.device?.type === "on_off_plug" || this.device?.type === "on_off_light"; }

  private async handleToggle() {
    try { await sendCommand(this.device.node_id, this.isOn ? "off" : "on"); } catch (e) { console.error("toggle failed:", e); }
  }

  render() {
    if (!this.device) return html``;
    return html`
      <div class="card ${this.stateClass}">
        <div class="header">
          <div class="icon">${this.icon}</div>
          <div class="info">
            <h3>${this.device.name || `Node ${this.device.node_id}`}</h3>
            <div class="type">${this.device.type} · Node ${this.device.node_id}</div>
          </div>
        </div>
        <div class="state-row">
          <div class="state-left">
            <div class="state-dot ${this.stateClass}"></div>
            <div class="state-label ${this.stateClass}">${this.stateText}</div>
          </div>
          ${this.hasToggle ? html`<button class="toggle ${this.isOn ? "on" : ""}" @click=${this.handleToggle}></button>` : ""}
        </div>
        <div class="meta">${this.protocol} · ${this.device.available ? "온라인" : "오프라인"}</div>
      </div>
    `;
  }
}
