import { LitElement, html, css, TemplateResult, nothing } from "lit";
import { customElement, property } from "lit/decorators.js";

interface A2UIComponent {
  type: string;
  props?: Record<string, any>;
  children?: A2UIComponent[];
}

interface SurfaceUpdate {
  surfaceId: string;
  components: A2UIComponent[];
}

@customElement("ha-a2ui-renderer")
export class A2UIRenderer extends LitElement {
  @property({ type: Object }) surface: SurfaceUpdate | null = null;

  static styles = css`
    :host { display: block; }

    .surface {
      background: #141824;
      border: 1px solid #2a2e3e;
      border-radius: 16px;
      padding: 16px;
    }

    .surface-header {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 12px;
      font-size: 11px;
      color: #6b7280;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .card {
      background: #1c2236;
      border-radius: 12px;
      padding: 16px;
      margin-bottom: 8px;
    }
    .card.outlined { border: 1px solid #2a2e3e; }
    .card.elevated { box-shadow: 0 4px 12px rgba(0,0,0,0.3); }

    .row {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
    }
    .column {
      display: flex;
      flex-direction: column;
    }

    .text-h3 { font-size: 20px; font-weight: 700; color: #e5e7eb; margin: 4px 0; }
    .text-h5 { font-size: 16px; font-weight: 600; color: #e5e7eb; margin: 4px 0; }
    .text-body { font-size: 14px; color: #d1d5db; line-height: 1.5; margin: 2px 0; }
    .text-caption { font-size: 12px; color: #6b7280; margin: 2px 0; }

    .icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
    }

    .divider {
      height: 1px;
      background: #2a2e3e;
      margin: 8px 0;
    }

    .btn {
      padding: 8px 16px;
      border-radius: 8px;
      border: none;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
    }
    .btn.filled { background: #03a9f4; color: #fff; }
    .btn.outlined { background: transparent; border: 1px solid #03a9f4; color: #03a9f4; }
  `;

  private iconMap: Record<string, string> = {
    door: "🚪", plug: "🔌", warning: "⚠️", check: "✅",
    light: "💡", sensor: "📡", home: "🏠", lock: "🔒",
    temperature: "🌡️", power: "⚡",
  };

  private renderComponent(comp: A2UIComponent): TemplateResult | typeof nothing {
    const p = comp.props || {};
    const children = comp.children || [];

    switch (comp.type) {
      case "Text":
        return html`<div class="text-${p.variant || 'body'}">${p.text || ''}</div>`;

      case "Card":
        return html`
          <div class="card ${p.variant || 'outlined'}">
            ${children.map(c => this.renderComponent(c))}
          </div>`;

      case "Row":
        return html`
          <div class="row" style="gap: ${p.gap || 8}px">
            ${children.map(c => this.renderComponent(c))}
          </div>`;

      case "Column":
        return html`
          <div class="column" style="gap: ${p.gap || 8}px">
            ${children.map(c => this.renderComponent(c))}
          </div>`;

      case "Icon":
        return html`
          <span class="icon" style="font-size: ${p.size || 24}px; color: ${p.color || 'inherit'}">
            ${this.iconMap[p.name] || '📦'}
          </span>`;

      case "Divider":
        return html`<div class="divider"></div>`;

      case "Button":
        return html`
          <button class="btn ${p.variant || 'filled'}"
            @click=${() => this.dispatchEvent(new CustomEvent("a2ui-action", {
              detail: { actionId: p.actionId }, bubbles: true, composed: true,
            }))}>
            ${p.label || 'Click'}
          </button>`;

      default:
        return html`<div style="color:#6b7280;font-size:12px">[${comp.type}]</div>`;
    }
  }

  render() {
    if (!this.surface || !this.surface.components?.length) return nothing;
    return html`
      <div class="surface">
        <div class="surface-header">✨ A2UI Surface: ${this.surface.surfaceId}</div>
        ${this.surface.components.map(c => this.renderComponent(c))}
      </div>
    `;
  }
}
