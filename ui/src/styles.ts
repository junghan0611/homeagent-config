import { css } from "lit";

export const globalStyles = css`
  :host {
    --bg: #0a0e1a;
    --surface: #141824;
    --surface-hover: #1c2236;
    --primary: #03a9f4;
    --primary-dim: rgba(3, 169, 244, 0.15);
    --success: #4caf50;
    --warning: #ff9800;
    --danger: #f44336;
    --text: #e5e7eb;
    --text-dim: #9ca3af;
    --border: #2a2e3e;
    --radius: 12px;

    display: block;
    font-family: system-ui, -apple-system, "Roboto", sans-serif;
    color: var(--text);
    background: var(--bg);
    min-height: 100vh;
    margin: 0;
  }

  * {
    box-sizing: border-box;
  }

  h1,
  h2,
  h3 {
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
    background: var(--primary);
    color: #fff;
  }
  .btn-primary:hover {
    background: #0288d1;
  }
  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
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
    background: rgba(76, 175, 80, 0.15);
    color: var(--success);
  }
  .badge-closed {
    background: rgba(244, 67, 54, 0.15);
    color: var(--danger);
  }
  .badge-sensor {
    background: var(--primary-dim);
    color: var(--primary);
  }
`;
