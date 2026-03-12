import { css } from "lit";

/**
 * 글로벌 CSS 변수 + 공통 스타일
 *
 * A2UI 인바리언트: 컴포넌트에서 #hex 색상 직접 사용 금지.
 * 모든 색상은 이 파일에 정의된 CSS 변수를 통해서만 참조.
 *
 * 테마 경로: Go surface.go → GET /api/home → app.ts applyTheme() → mood 클래스 전환
 */
export const globalStyles = css`
  :host {
    /* ─── Base palette ─── */
    --ha-bg: #0a0e1a;
    --ha-surface: #141824;
    --ha-surface-hover: #1c2236;
    --ha-surface-alt: #242a3e;
    --ha-border: #2a2e3e;
    --ha-border-subtle: rgba(255, 255, 255, 0.03);

    /* ─── Text ─── */
    --ha-text: #e5e7eb;
    --ha-text-secondary: #d1d5db;
    --ha-text-muted: #9ca3af;
    --ha-text-dim: #6b7280;
    --ha-text-faint: #4b5563;

    /* ─── Accent ─── */
    --ha-primary: #03a9f4;
    --ha-primary-hover: #0288d1;
    --ha-primary-dim: rgba(3, 169, 244, 0.15);
    --ha-primary-glow: rgba(3, 169, 244, 0.3);

    /* ─── Semantic ─── */
    --ha-success: #4caf50;
    --ha-success-dim: rgba(76, 175, 80, 0.15);
    --ha-success-glow: rgba(76, 175, 80, 0.5);
    --ha-warning: #ff9800;
    --ha-error: #f44336;
    --ha-error-dim: rgba(244, 67, 54, 0.1);
    --ha-error-glow: rgba(244, 67, 54, 0.5);

    /* ─── Misc ─── */
    --ha-white: #fff;
    --ha-overlay: rgba(0, 0, 0, 0.6);
    --ha-radius: 12px;
    --ha-radius-lg: 16px;

    /* ─── Chat ─── */
    --ha-chat-user-bg: #1e3a5f;
    --ha-chat-user-text: #93c5fd;

    display: block;
    font-family: system-ui, -apple-system, "Roboto", sans-serif;
    color: var(--ha-text);
    background: var(--ha-bg);
    min-height: 100vh;
    margin: 0;
  }

  /* Time-based page themes — only redefine variables, never raw colors in components */
  :host(.mood-morning)   { --ha-bg: #1a1208; --ha-surface: #241a0c; --ha-border: #4a3510; --ha-primary: #FF9800; }
  :host(.mood-forenoon)  { --ha-bg: #1a1808; --ha-surface: #24200c; --ha-border: #4a4510; --ha-primary: #FFC107; }
  :host(.mood-noon)      { --ha-bg: #1a1008; --ha-surface: #24180c; --ha-border: #4a2810; --ha-primary: #FF5722; }
  :host(.mood-afternoon) { --ha-bg: #081420; --ha-surface: #0c1c2c; --ha-border: #163050; --ha-primary: #03A9F4; }
  :host(.mood-evening)   { --ha-bg: #100820; --ha-surface: #180c2c; --ha-border: #2a1650; --ha-primary: #7C4DFF; }
  :host(.mood-night)     { --ha-bg: #08081a; --ha-surface: #0e0e24; --ha-border: #1a1a40; --ha-primary: #5C6BC0; }
  :host(.mood-latenight) { --ha-bg: #050508; --ha-surface: #0a0a12; --ha-border: #14141e; --ha-primary: #37474F; }

  * {
    box-sizing: border-box;
  }

  h1, h2, h3 {
    margin: 0;
    font-weight: 600;
  }

  button {
    cursor: pointer;
    border: none;
    border-radius: 8px;
    padding: 10px 20px;
    font-size: 14px;
    font-weight: 500;
    transition: all 0.15s ease;
  }

  .btn-primary {
    background: var(--ha-primary);
    color: var(--ha-white);
  }
  .btn-primary:hover {
    background: var(--ha-primary-hover);
  }
  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .card {
    background: var(--ha-surface);
    border: 1px solid var(--ha-border);
    border-radius: var(--ha-radius);
    padding: 20px;
  }

  .badge {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: 600;
  }
  .badge-open {
    background: var(--ha-success-dim);
    color: var(--ha-success);
  }
  .badge-closed {
    background: var(--ha-error-dim);
    color: var(--ha-error);
  }
  .badge-sensor {
    background: var(--ha-primary-dim);
    color: var(--ha-primary);
  }
`;
