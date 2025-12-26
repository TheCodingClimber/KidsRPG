import { useEffect, useState } from "react";
import { getJson, delJson } from "../net/api";

type CharacterRow = {
  id: string;
  name: string;
  race: string;
  class: string;
  background: string;
  personality: number;
  level: number;
  gold: number;
};

export default function LoadGame({
  onLoad,
}: {
  onLoad: (characterId: string) => void;
}) {
  const [chars, setChars] = useState<CharacterRow[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function refresh() {
    setError("");
    setLoading(true);
    try {
      const data = await getJson<{ characters: CharacterRow[] }>("/characters");
      setChars(data.characters ?? []);
    } catch (e: any) {
      setError(e.message || "Failed to load characters");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleDelete(c: CharacterRow) {
    const ok = window.confirm(
      `Delete "${c.name}" (Level ${c.level})?\n\nThis cannot be undone.`
    );
    if (!ok) return;

    setBusyId(c.id);
    setError("");

    try {
      await delJson(`/characters/${c.id}`);
      // Fast local update
      setChars((prev) => prev.filter((x) => x.id !== c.id));
    } catch (e: any) {
      setError(e.message || "Failed to delete character");
    } finally {
      setBusyId(null);
    }
  }

  if (loading) {
    return <div style={{ padding: 24 }}>Loading characters…</div>;
  }

  return (
    <div style={{ padding: 24 }}>
      <h2>Load Game</h2>

      {error && (
        <div style={{ color: "crimson", marginBottom: 12 }}>
          {error}
        </div>
      )}

      {chars.length === 0 ? (
        <div style={{ opacity: 0.8 }}>
          No characters yet. Go back and create one.
        </div>
      ) : (
        <div style={{ display: "grid", gap: 10, maxWidth: 680 }}>
          {chars.map((c) => (
            <div
              key={c.id}
              style={{
                border: "1px solid #333",
                borderRadius: 10,
                padding: 12,
                display: "grid",
                gridTemplateColumns: "1fr auto",
                gap: 10,
                alignItems: "center",
              }}
            >
              {/* Load */}
              <button
                onClick={() => onLoad(c.id)}
                disabled={busyId === c.id}
                style={{
                  textAlign: "left",
                  padding: 0,
                  border: "none",
                  background: "transparent",
                  cursor: "pointer",
                }}
              >
                <div style={{ fontWeight: 800, fontSize: 16 }}>{c.name}</div>
                <div style={{ opacity: 0.85 }}>
                  Lv {c.level} {c.race} {c.class} • {c.background} • {c.gold}g
                </div>
                <div style={{ opacity: 0.7, fontSize: 12 }}>
                  Personality: {c.personality}/100
                </div>
              </button>

              {/* Delete */}
              <button
                onClick={() => handleDelete(c)}
                disabled={busyId === c.id}
                style={{
                  padding: "6px 10px",
                  borderRadius: 8,
                  border: "1px solid rgba(200,0,0,0.4)",
                  background: "rgba(200,0,0,0.1)",
                  cursor: "pointer",
                  whiteSpace: "nowrap",
                }}
              >
                {busyId === c.id ? "Deleting…" : "Delete"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
