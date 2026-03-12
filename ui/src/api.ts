// HomeAgent API client

export interface DeviceState {
  node_id: number;
  name: string;
  type: string;
  available: boolean;
  state: Record<string, unknown>;
}

export interface HubEvent {
  type: string; // "device_state" | "device_added" | "commission_result"
  device_id: number;
  key?: string;
  value?: unknown;
}

const API_BASE = "";

export async function getDevices(): Promise<DeviceState[]> {
  const res = await fetch(`${API_BASE}/api/devices`);
  if (!res.ok) throw new Error(`Failed to fetch devices: ${res.statusText}`);
  return res.json();
}

export interface ChatResult {
  reply: string;
  actions?: { action: string; node_id: number }[];
}

export async function getHomeSurface(): Promise<any> {
  const res = await fetch(`${API_BASE}/api/home`);
  if (!res.ok) throw new Error("Failed to load home surface");
  return res.json();
}

export async function chat(message: string): Promise<ChatResult> {
  const res = await fetch(`${API_BASE}/api/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Chat failed");
  }
  return res.json();
}

export async function sendCommand(nodeId: number, command: string): Promise<void> {
  const res = await fetch(`${API_BASE}/api/devices/command`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ node_id: nodeId, command }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Command failed");
  }
}

export async function commission(code: string, networkOnly = true): Promise<{ status: string }> {
  const res = await fetch(`${API_BASE}/api/commission`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code, network_only: networkOnly }),
  });
  if (!res.ok && res.status !== 202) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Commission failed");
  }
  return res.json();
}

export function subscribeEvents(
  onEvent: (event: HubEvent) => void,
  onError?: (err: Event) => void,
): EventSource {
  const es = new EventSource(`${API_BASE}/api/events`);
  es.onmessage = (e) => {
    try {
      const evt: HubEvent = JSON.parse(e.data);
      onEvent(evt);
    } catch {
      // ignore parse errors
    }
  };
  es.onerror = (e) => {
    if (onError) onError(e);
  };
  return es;
}
