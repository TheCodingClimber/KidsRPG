const API_BASE = `http://${location.hostname}:3030`;

function authHeaders(): HeadersInit {
  const sessionId = localStorage.getItem("sessionId") || "";
  return sessionId ? { "x-session-id": sessionId } : {};
}

async function readJsonSafely(res: Response) {
  return res.json().catch(() => ({}));
}

export async function getJson<T>(path: string): Promise<T> {
  const headers: HeadersInit = {
    ...authHeaders(),
  };

  const res = await fetch(`${API_BASE}${path}`, { headers } satisfies RequestInit);

  const data = await readJsonSafely(res);
  if (!res.ok) throw new Error((data as any)?.error || `HTTP ${res.status}`);
  return data as T;
}

export async function postJson<T>(path: string, body: any): Promise<T> {
  const headers: HeadersInit = {
    "Content-Type": "application/json",
    ...authHeaders(),
  };

  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  } satisfies RequestInit);

  const data = await readJsonSafely(res);
  if (!res.ok) throw new Error((data as any)?.error || `HTTP ${res.status}`);
  return data as T;
}

export async function delJson<T>(path: string): Promise<T> {
  const headers: HeadersInit = {
    ...authHeaders(),
  };

  const res = await fetch(`${API_BASE}${path}`, {
    method: "DELETE",
    headers,
  } satisfies RequestInit);

  const data = await readJsonSafely(res);
  if (!res.ok) throw new Error((data as any)?.error || `HTTP ${res.status}`);
  return data as T;
}

// Optional helper (you already had this pattern in Game.tsx)
export async function fastTravel(characterId: string, regionId: string, settlementId: string) {
  return postJson<{
    ok: boolean;
    fee: number;
    settlementName: string;
    character: { id: string; gold: number };
    save: { region_id: string; x: number; y: number; last_seen_at: number; state_json: string };
  }>(`/game/fast-travel/${characterId}`, { regionId, settlementId });
}
