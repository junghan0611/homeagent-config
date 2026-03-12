import { LitElement, html, css, TemplateResult, nothing } from "lit";
import { customElement, property } from "lit/decorators.js";

interface A2UIComponent { type: string; props?: Record<string, any>; children?: A2UIComponent[]; }
interface SurfaceTheme { accent?: string; bg?: string; mood?: string; }
interface SurfaceUpdate { surfaceId: string; components: A2UIComponent[]; theme?: SurfaceTheme; }

@customElement("ha-a2ui-renderer")
export class A2UIRenderer extends LitElement {
  @property({ type: Object }) surface: SurfaceUpdate | null = null;

  static styles = css`
    :host { display: block; }

    .surface {
      border-radius: var(--ha-radius-lg, 16px);
      padding: 20px;
      background: var(--ha-surface, #141824);
      border: 1px solid var(--ha-border, #2a2e3e);
      transition: background 0.5s ease, border-color 0.5s ease;
    }
    .surface-header { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; font-size: 11px; color: var(--ha-text-dim, #6b7280); text-transform: uppercase; letter-spacing: 0.5px; }

    /* Mood-based surfaces — use variable definitions only in this scope */
    .surface.mood-morning   { --_s-bg-from: #2d1f0a; --_s-bg-to: #1a1208; --_s-border: #6d4c1a; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }
    .surface.mood-forenoon  { --_s-bg-from: #2a2408; --_s-bg-to: #1c1a0a; --_s-border: #5c5010; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }
    .surface.mood-noon      { --_s-bg-from: #2d1808; --_s-bg-to: #1c1008; --_s-border: #6d3010; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }
    .surface.mood-afternoon { --_s-bg-from: #0c1e35; --_s-bg-to: #0a1525; --_s-border: #1a4070; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }
    .surface.mood-evening   { --_s-bg-from: #1e0c35; --_s-bg-to: #150a25; --_s-border: #3a1a70; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }
    .surface.mood-night     { --_s-bg-from: #0e0e25; --_s-bg-to: #0a0a18; --_s-border: #2525aa; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }
    .surface.mood-latenight { --_s-bg-from: #080810; --_s-bg-to: #050508; --_s-border: #1a1a2a; background: linear-gradient(135deg, var(--_s-bg-from) 0%, var(--_s-bg-to) 100%); border: 1px solid var(--_s-border); }

    .card { background: var(--ha-surface-hover, #1c2236); border-radius: 12px; padding: 16px; margin-bottom: 8px; }
    .card.outlined { border: 1px solid var(--ha-border, #2a2e3e); }
    .card.elevated { box-shadow: 0 4px 12px rgba(0,0,0,0.3); }

    .row { display: flex; align-items: center; flex-wrap: wrap; }
    .column { display: flex; flex-direction: column; }

    .text-h3 { font-size: 20px; font-weight: 700; color: var(--ha-text, #e5e7eb); margin: 4px 0; }
    .text-h5 { font-size: 16px; font-weight: 600; color: var(--ha-text, #e5e7eb); margin: 4px 0; }
    .text-body { font-size: 14px; color: var(--ha-text-secondary, #d1d5db); line-height: 1.5; margin: 2px 0; }
    .text-caption { font-size: 12px; color: var(--ha-text-dim, #6b7280); margin: 2px 0; }

    .icon { display: inline-flex; align-items: center; justify-content: center; }
    .divider { height: 1px; background: var(--ha-border, #2a2e3e); margin: 8px 0; }

    .btn { padding: 8px 16px; border-radius: 8px; border: none; font-size: 13px; font-weight: 600; cursor: pointer; }
    .btn.filled { background: var(--ha-primary, #03a9f4); color: var(--ha-white, #fff); }
    .btn.outlined { background: transparent; border: 1px solid var(--ha-primary, #03a9f4); color: var(--ha-primary, #03a9f4); }
  `;

  private iconMap: Record<string, string> = {
    door: "🚪", plug: "🔌", warning: "⚠️", check: "✅",
    light: "💡", sensor: "📡", home: "🏠", lock: "🔒",
    temperature: "🌡️", power: "⚡", sunrise: "🌅", sun: "☀️",
  };

  private renderComponent(comp: A2UIComponent): TemplateResult | typeof nothing {
    const p = comp.props || {};
    const children = comp.children || [];
    switch (comp.type) {
      case "Text": return html`<div class="text-${p.variant || 'body'}">${p.text || ''}</div>`;
      case "Card": return html`<div class="card ${p.variant || 'outlined'}">${children.map(c => this.renderComponent(c))}</div>`;
      case "Row": return html`<div class="row" style="gap: ${p.gap || 8}px">${children.map(c => this.renderComponent(c))}</div>`;
      case "Column": return html`<div class="column" style="gap: ${p.gap || 8}px">${children.map(c => this.renderComponent(c))}</div>`;
      case "Icon": return html`<span class="icon" style="font-size: ${p.size || 24}px; color: ${p.color || 'inherit'}">${this.iconMap[p.name] || '📦'}</span>`;
      case "Divider": return html`<div class="divider"></div>`;
      case "Button": return html`<button class="btn ${p.variant || 'filled'}" @click=${() => this.dispatchEvent(new CustomEvent("a2ui-action", { detail: { actionId: p.actionId }, bubbles: true, composed: true }))}>${p.label || 'Click'}</button>`;
      default: return html`<div style="color: var(--ha-text-dim); font-size: 12px">[${comp.type}]</div>`;
    }
  }

  render() {
    if (!this.surface || !this.surface.components?.length) return nothing;
    const mood = this.surface.theme?.mood || "";
    return html`<div class="surface mood-${mood}">${this.surface.components.map(c => this.renderComponent(c))}</div>`;
  }
}
