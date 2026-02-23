import { LitElement, html, css } from "lit";
import { customElement, property, state } from "lit/decorators.js";
import { commission } from "./api.js";

@customElement("ha-commission-dialog")
export class CommissionDialog extends LitElement {
  @property({ type: Boolean })
  open = false;

  @state()
  private code = "";

  @state()
  private loading = false;

  @state()
  private error = "";

  static styles = css`
    :host {
      display: block;
    }

    .overlay {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.6);
      backdrop-filter: blur(4px);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 100;
      animation: fadeIn 0.2s ease;
    }

    @keyframes fadeIn {
      from { opacity: 0; }
      to { opacity: 1; }
    }

    .dialog {
      background: #141824;
      border: 1px solid #2a2e3e;
      border-radius: 20px;
      padding: 32px;
      width: 380px;
      max-width: 90vw;
    }

    h2 {
      margin: 0 0 8px;
      font-size: 20px;
      color: #e5e7eb;
    }

    .desc {
      color: #9ca3af;
      font-size: 13px;
      margin-bottom: 20px;
      line-height: 1.5;
    }

    input {
      width: 100%;
      padding: 12px 16px;
      border-radius: 10px;
      border: 1px solid #2a2e3e;
      background: #0a0e1a;
      color: #e5e7eb;
      font-size: 18px;
      font-family: "JetBrains Mono", monospace;
      letter-spacing: 2px;
      text-align: center;
      outline: none;
      transition: border-color 0.2s;
    }
    input:focus {
      border-color: #03a9f4;
    }
    input::placeholder {
      color: #4b5563;
      letter-spacing: 1px;
      font-size: 14px;
    }

    .actions {
      display: flex;
      gap: 10px;
      margin-top: 20px;
    }
    .actions button {
      flex: 1;
      padding: 12px;
      border-radius: 10px;
      font-size: 14px;
      font-weight: 600;
      border: none;
      cursor: pointer;
    }
    .btn-cancel {
      background: #1c2236;
      color: #9ca3af;
    }
    .btn-cancel:hover {
      background: #242a3e;
    }
    .btn-pair {
      background: #03a9f4;
      color: #fff;
    }
    .btn-pair:hover {
      background: #0288d1;
    }
    .btn-pair:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .error {
      margin-top: 12px;
      padding: 10px;
      border-radius: 8px;
      background: rgba(244, 67, 54, 0.1);
      color: #f44336;
      font-size: 13px;
    }

    .spinner {
      display: inline-block;
      width: 16px;
      height: 16px;
      border: 2px solid rgba(255,255,255,0.3);
      border-top-color: #fff;
      border-radius: 50%;
      animation: spin 0.6s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  `;

  private async handlePair() {
    if (!this.code.trim() || this.loading) return;

    this.loading = true;
    this.error = "";

    try {
      await commission(this.code.trim());
      // Commission is async (60-120s). Result comes via SSE event.
      this.dispatchEvent(
        new CustomEvent("commissioned", { bubbles: true })
      );
      this.code = "";
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
          <div class="desc">
            Matter 디바이스의 Setup Code를 입력하세요.<br />
            디바이스가 페어링 모드인지 확인해 주세요.
          </div>

          <input
            type="text"
            placeholder="0000-000-0000"
            .value=${this.code}
            @input=${(e: InputEvent) => {
              this.code = (e.target as HTMLInputElement).value;
            }}
            @keydown=${(e: KeyboardEvent) => {
              if (e.key === "Enter") this.handlePair();
            }}
            ?disabled=${this.loading}
          />

          ${this.error ? html`<div class="error">${this.error}</div>` : ""}

          <div class="actions">
            <button class="btn-cancel" @click=${this.handleClose} ?disabled=${this.loading}>
              취소
            </button>
            <button
              class="btn-pair"
              @click=${this.handlePair}
              ?disabled=${!this.code.trim() || this.loading}
            >
              ${this.loading ? html`<span class="spinner"></span> 페어링 중...` : "페어링 시작"}
            </button>
          </div>
        </div>
      </div>
    `;
  }
}
