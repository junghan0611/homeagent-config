import { LitElement, html, css } from "lit";
import { customElement, property } from "lit/decorators.js";
import type { DeviceState } from "./api.js";

@customElement("ha-device-card")
export class DeviceCard extends LitElement {
  @property({ type: Object })
  device!: DeviceState;

  static styles = css`
    :host {
      display: block;
    }

    .card {
      background: #141824;
      border: 1px solid #2a2e3e;
      border-radius: 16px;
      padding: 24px;
      transition: all 0.3s ease;
      position: relative;
      overflow: hidden;
    }

    .card::before {
      content: "";
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 3px;
      background: var(--accent, #03a9f4);
      transition: background 0.3s ease;
    }

    .card.open::before {
      background: #4caf50;
    }
    .card.closed::before {
      background: #f44336;
    }

    .header {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 16px;
    }

    .icon {
      font-size: 32px;
      width: 48px;
      height: 48px;
      display: flex;
      align-items: center;
      justify-content: center;
      border-radius: 12px;
      background: rgba(3, 169, 244, 0.1);
    }

    .info h3 {
      font-size: 16px;
      font-weight: 600;
      color: #e5e7eb;
      margin: 0;
    }

    .info .type {
      font-size: 12px;
      color: #9ca3af;
      margin-top: 2px;
    }

    .state {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px 16px;
      background: rgba(255, 255, 255, 0.03);
      border-radius: 10px;
    }

    .state-dot {
      width: 12px;
      height: 12px;
      border-radius: 50%;
      transition: all 0.3s ease;
    }
    .state-dot.open {
      background: #4caf50;
      box-shadow: 0 0 8px rgba(76, 175, 80, 0.5);
    }
    .state-dot.closed {
      background: #f44336;
      box-shadow: 0 0 8px rgba(244, 67, 54, 0.5);
    }

    .state-label {
      font-size: 18px;
      font-weight: 600;
    }
    .state-label.open {
      color: #4caf50;
    }
    .state-label.closed {
      color: #f44336;
    }

    .meta {
      margin-top: 12px;
      font-size: 11px;
      color: #6b7280;
    }
  `;

  private get isOpen(): boolean {
    return this.device?.state?.contact === true;
  }

  private get stateClass(): string {
    return this.isOpen ? "open" : "closed";
  }

  private get icon(): string {
    switch (this.device?.type) {
      case "contact_sensor":
        return this.isOpen ? "🚪" : "🔒";
      case "on_off_light":
        return "💡";
      case "on_off_plug":
        return "🔌";
      default:
        return "📡";
    }
  }

  private get stateText(): string {
    switch (this.device?.type) {
      case "contact_sensor":
        return this.isOpen ? "열림 (Open)" : "닫힘 (Closed)";
      default:
        return JSON.stringify(this.device?.state || {});
    }
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

        <div class="state">
          <div class="state-dot ${this.stateClass}"></div>
          <div class="state-label ${this.stateClass}">${this.stateText}</div>
        </div>

        <div class="meta">
          Matter over Thread · ${this.device.available ? "온라인" : "오프라인"}
        </div>
      </div>
    `;
  }
}
