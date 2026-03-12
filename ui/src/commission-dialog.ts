import { LitElement, html, css } from "lit";
import { customElement, property, state } from "lit/decorators.js";
import { commission } from "./api.js";

@customElement("ha-commission-dialog")
export class CommissionDialog extends LitElement {
  @property({ type: Boolean }) open = false;

  @state() private code = "";
  @state() private ssid = "";
  @state() private password = "";
  @state() private networkOnly = true;
  @state() private loading = false;
  @state() private error = "";

  static styles = css`
    :host { display: block; }

    .overlay { position: fixed; inset: 0; background: var(--ha-overlay, rgba(0,0,0,0.6)); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; z-index: 100; animation: fadeIn 0.2s ease; }
    @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }

    .dialog { background: var(--ha-surface, #141824); border: 1px solid var(--ha-border, #2a2e3e); border-radius: 20px; padding: 32px; width: 420px; max-width: 90vw; }

    h2 { margin: 0 0 8px; font-size: 20px; color: var(--ha-text, #e5e7eb); }
    .desc { color: var(--ha-text-muted, #9ca3af); font-size: 13px; margin-bottom: 20px; line-height: 1.5; }

    .field { margin-bottom: 12px; }
    .field label { display: block; font-size: 12px; color: var(--ha-text-muted, #9ca3af); margin-bottom: 4px; font-weight: 600; }

    input { width: 100%; padding: 12px 16px; border-radius: 10px; border: 1px solid var(--ha-border, #2a2e3e); background: var(--ha-bg, #0a0e1a); color: var(--ha-text, #e5e7eb); font-size: 14px; outline: none; transition: border-color 0.2s; }
    input:focus { border-color: var(--ha-primary, #03a9f4); }
    input::placeholder { color: var(--ha-text-faint, #4b5563); }
    input.code { font-size: 18px; font-family: "JetBrains Mono", monospace; letter-spacing: 2px; text-align: center; }

    /* Mode selector */
    .mode-row { display: flex; gap: 8px; margin-bottom: 16px; }
    .mode-btn { flex: 1; padding: 10px; border-radius: 10px; border: 1px solid var(--ha-border, #2a2e3e); background: var(--ha-bg, #0a0e1a); color: var(--ha-text-muted, #9ca3af); font-size: 13px; font-weight: 600; cursor: pointer; text-align: center; transition: all 0.15s; }
    .mode-btn.active { border-color: var(--ha-primary, #03a9f4); color: var(--ha-primary, #03a9f4); background: var(--ha-primary-dim, rgba(3,169,244,0.15)); }
    .mode-btn:hover:not(.active) { background: var(--ha-surface-hover, #1c2236); }

    .wifi-fields { overflow: hidden; transition: max-height 0.3s ease, opacity 0.3s ease; }
    .wifi-fields.hidden { max-height: 0; opacity: 0; margin: 0; }
    .wifi-fields.visible { max-height: 200px; opacity: 1; }

    .actions { display: flex; gap: 10px; margin-top: 20px; }
    .actions button { flex: 1; padding: 12px; border-radius: 10px; font-size: 14px; font-weight: 600; border: none; cursor: pointer; }
    .btn-cancel { background: var(--ha-surface-hover, #1c2236); color: var(--ha-text-muted, #9ca3af); }
    .btn-cancel:hover { background: var(--ha-surface-alt, #242a3e); }
    .btn-pair { background: var(--ha-primary, #03a9f4); color: var(--ha-white, #fff); }
    .btn-pair:hover { background: var(--ha-primary-hover, #0288d1); }
    .btn-pair:disabled { opacity: 0.5; cursor: not-allowed; }

    .error { margin-top: 12px; padding: 10px; border-radius: 8px; background: var(--ha-error-dim, rgba(244,67,54,0.1)); color: var(--ha-error, #f44336); font-size: 13px; }

    .spinner { display: inline-block; width: 16px; height: 16px; border: 2px solid rgba(255,255,255,0.3); border-top-color: var(--ha-white, #fff); border-radius: 50%; animation: spin 0.6s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
  `;

  private async handlePair() {
    if (!this.code.trim() || this.loading) return;
    this.loading = true;
    this.error = "";

    try {
      // WiFi 커미셔닝 시 credentials 먼저 설정
      if (!this.networkOnly && this.ssid.trim()) {
        const res = await fetch("/api/wifi-credentials", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ssid: this.ssid.trim(), password: this.password }),
        });
        if (!res.ok && res.status !== 204) {
          throw new Error("WiFi credentials 설정 실패");
        }
      }

      await commission(this.code.trim(), this.networkOnly);
      this.dispatchEvent(new CustomEvent("commissioned", { bubbles: true }));
      this.code = "";
      this.ssid = "";
      this.password = "";
      this.open = false;
    } catch (e) {
      this.error = e instanceof Error ? e.message : "페어링 실패";
    } finally {
      this.loading = false;
    }
  }

  private handleClose() {
    this.open = false;
    this.code = "";
    this.error = "";
    this.dispatchEvent(new CustomEvent("close", { bubbles: true }));
  }

  render() {
    if (!this.open) return html``;
    return html`
      <div class="overlay" @click=${this.handleClose}>
        <div class="dialog" @click=${(e: Event) => e.stopPropagation()}>
          <h2>🔗 디바이스 페어링</h2>
          <div class="desc">Matter 디바이스의 Setup Code를 입력하세요.</div>

          <div class="field">
            <label>Setup Code</label>
            <input class="code" type="text" placeholder="0000-000-0000"
              .value=${this.code}
              @input=${(e: InputEvent) => { this.code = (e.target as HTMLInputElement).value; }}
              @keydown=${(e: KeyboardEvent) => { if (e.key === "Enter") this.handlePair(); }}
              ?disabled=${this.loading} />
          </div>

          <div class="mode-row">
            <button class="mode-btn ${this.networkOnly ? 'active' : ''}"
              @click=${() => { this.networkOnly = true; }}>📡 네트워크 검색</button>
            <button class="mode-btn ${!this.networkOnly ? 'active' : ''}"
              @click=${() => { this.networkOnly = false; }}>📶 WiFi (BLE)</button>
          </div>

          <div class="wifi-fields ${this.networkOnly ? 'hidden' : 'visible'}">
            <div class="field">
              <label>WiFi SSID</label>
              <input type="text" placeholder="WiFi 네트워크 이름"
                .value=${this.ssid}
                @input=${(e: InputEvent) => { this.ssid = (e.target as HTMLInputElement).value; }}
                ?disabled=${this.loading} />
            </div>
            <div class="field">
              <label>WiFi Password</label>
              <input type="password" placeholder="WiFi 비밀번호"
                .value=${this.password}
                @input=${(e: InputEvent) => { this.password = (e.target as HTMLInputElement).value; }}
                ?disabled=${this.loading} />
            </div>
          </div>

          ${this.error ? html`<div class="error">${this.error}</div>` : ""}

          <div class="actions">
            <button class="btn-cancel" @click=${this.handleClose} ?disabled=${this.loading}>취소</button>
            <button class="btn-pair" @click=${this.handlePair} ?disabled=${!this.code.trim() || this.loading}>
              ${this.loading ? html`<span class="spinner"></span> 페어링 중...` : "페어링 시작"}
            </button>
          </div>
        </div>
      </div>
    `;
  }
}
