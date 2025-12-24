import { useEffect, useState } from "react";
import { getJson } from "../net/api";

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

  useEffect(() => {
    (async () => {
      try {
        const data = await getJson<{ characters: CharacterRow[] }>("/characters");
        setChars(data.characters ?? []);
      } catch (e: any) {
        setError(e.message || "Failed to load characters");
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  if (loading) {
    return <div style={{ padding: 24 }}>Loading characters…</div>;
  }

  return (
    <div style={{ padding: 24 }}>
      <h2>Load Game</h2>

      {error && <div style={{ color: "crimson", marginBottom: 12 }}>{error}</div>}

      {chars.length === 0 ? (
        <div style={{ opacity: 0.8 }}>
          No characters yet. Go back and create one.
        </div>
      ) : (
        <div style={{ display: "grid", gap: 10, maxWidth: 640 }}>
          {chars.map((c) => (
            <button
              key={c.id}
              onClick={() => onLoad(c.id)}
              style={{
                textAlign: "left",
                padding: 12,
                border: "1px solid #333",
                borderRadius: 8,
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
          ))}
        </div>
      )}
    </div>
  );
}
