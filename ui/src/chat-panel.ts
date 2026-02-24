import { LitElement, html, css } from "lit";
import { customElement, state } from "lit/decorators.js";
import { chat } from "./api.js";

interface Message {
  role: "user" | "agent";
  text: string;
  actions?: string;
}

@customElement("ha-chat-panel")
export class ChatPanel extends LitElement {
  @state() private messages: Message[] = [];
  @state() private input = "";
  @state() private loading = false;

  static styles = css`
    :host { display: block; }

    .panel {
      background: var(--surface, #141824);
      border: 1px solid var(--border, #2a2e3e);
      border-radius: 16px;
      overflow: hidden;
    }

    .header {
      padding: 16px 20px;
      border-bottom: 1px solid #2a2e3e;
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 14px;
      font-weight: 600;
      color: #e5e7eb;
    }

    .messages {
      padding: 16px;
      max-height: 300px;
      overflow-y: auto;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .msg {
      max-width: 85%;
      padding: 10px 14px;
      border-radius: 12px;
      font-size: 14px;
      line-height: 1.5;
    }

    .msg.user {
      align-self: flex-end;
      background: #1e3a5f;
      color: #93c5fd;
      border-bottom-right-radius: 4px;
    }

    .msg.agent {
      align-self: flex-start;
      background: var(--surface-hover, #1c2236);
      color: #d1d5db;
      border-bottom-left-radius: 4px;
    }

    .msg .action-badge {
      display: inline-block;
      margin-top: 6px;
      padding: 3px 8px;
      border-radius: 6px;
      background: rgba(76, 175, 80, 0.15);
      color: #4caf50;
      font-size: 11px;
      font-family: monospace;
    }

    .empty {
      padding: 24px;
      text-align: center;
      color: #6b7280;
      font-size: 13px;
    }

    .input-row {
      display: flex;
      gap: 8px;
      padding: 12px 16px;
      border-top: 1px solid #2a2e3e;
    }

    input {
      flex: 1;
      padding: 10px 14px;
      border-radius: 10px;
      border: 1px solid var(--border, #2a2e3e);
      background: var(--bg, #0a0e1a);
      color: #e5e7eb;
      font-size: 14px;
      outline: none;
    }
    input:focus { border-color: #03a9f4; }
    input::placeholder { color: #4b5563; }

    button {
      padding: 10px 20px;
      border-radius: 10px;
      border: none;
      background: #03a9f4;
      color: #fff;
      font-weight: 600;
      font-size: 14px;
      cursor: pointer;
    }
    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }
    button:hover:not(:disabled) { background: #0288d1; }

    .typing {
      color: #6b7280;
      font-size: 13px;
      padding: 4px 14px;
    }
    .typing::after {
      content: "...";
      animation: dots 1s steps(3) infinite;
    }
    @keyframes dots {
      0% { content: "."; }
      33% { content: ".."; }
      66% { content: "..."; }
    }
  `;

  /** Called externally (e.g. from SSE agent_message events) */
  public addAgentMessage(text: string) {
    this.messages = [...this.messages, { role: "agent", text }];
    this.updateComplete.then(() => {
      const el = this.shadowRoot?.querySelector(".messages");
      if (el) el.scrollTop = el.scrollHeight;
    });
  }

  private async handleSend() {
    const msg = this.input.trim();
    if (!msg || this.loading) return;

    this.messages = [...this.messages, { role: "user", text: msg }];
    this.input = "";
    this.loading = true;

    try {
      const result = await chat(msg);
      const actionsText = result.actions?.map(
        a => `${a.action} → Node ${a.node_id}`
      ).join(", ");

      this.messages = [...this.messages, {
        role: "agent",
        text: result.reply,
        actions: actionsText,
      }];
    } catch (e) {
      this.messages = [...this.messages, {
        role: "agent",
        text: `⚠️ ${e instanceof Error ? e.message : "오류 발생"}`,
      }];
    } finally {
      this.loading = false;
      this.updateComplete.then(() => {
        const el = this.shadowRoot?.querySelector(".messages");
        if (el) el.scrollTop = el.scrollHeight;
      });
    }
  }

  render() {
    return html`
      <div class="panel">
        <div class="header">🤖 HomeAgent 채팅</div>

        <div class="messages">
          ${this.messages.length === 0
            ? html`<div class="empty">디바이스에 대해 물어보세요<br/>"플러그 켜줘", "문 열려있어?"</div>`
            : this.messages.map(m => html`
                <div class="msg ${m.role}">
                  ${m.text}
                  ${m.actions ? html`<div class="action-badge">⚡ ${m.actions}</div>` : ""}
                </div>
              `)}
          ${this.loading ? html`<div class="typing">생각하는 중</div>` : ""}
        </div>

        <div class="input-row">
          <input
            placeholder="메시지를 입력하세요..."
            .value=${this.input}
            @input=${(e: InputEvent) => { this.input = (e.target as HTMLInputElement).value; }}
            @keydown=${(e: KeyboardEvent) => { if (e.key === "Enter") this.handleSend(); }}
            ?disabled=${this.loading}
          />
          <button @click=${this.handleSend} ?disabled=${!this.input.trim() || this.loading}>
            전송
          </button>
        </div>
      </div>
    `;
  }
}
