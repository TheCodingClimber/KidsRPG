import { useEffect, useState } from "react";
import { getJson, postJson } from "../net/api";

type BackpackItem = {
  itemId: string;
  name: string;
  slot: string;
  rarity: string;
  statsJson: string;
};

export default function BackpackModal({
  open,
  onClose,
  characterId,
}: {
  open: boolean;
  onClose: () => void;
  characterId: string;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [items, setItems] = useState<BackpackItem[]>([]);

  async function load() {
    setLoading(true);
    setError("");
    try {
      const res = await getJson<{ items: BackpackItem[] }>(`/inventory/${characterId}`);
      setItems(Array.isArray(res.items) ? res.items : []);
    } catch (e: any) {
      setError(e?.message || "Failed to load backpack");
      setItems([]);
    } finally {
      setLoading(false);
    }
  }

  async function drop(itemId: string) {
    try {
      await postJson(`/inventory/drop/${characterId}`, { itemId });
      await load();
    } catch (e: any) {
      setError(e?.message || "Failed to drop item");
    }
  }

  useEffect(() => {
    if (!open) return;
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, characterId]);

  if (!open) return null;

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.55)",
        display: "grid",
        placeItems: "center",
        padding: 12,
        zIndex: 9999,
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: "min(560px, 95vw)",
          maxHeight: "80vh",
          overflow: "auto",
          background: "#0f1115",
          color: "#f2f2f2",
          borderRadius: 12,
          border: "1px solid #2b2b2b",
          padding: 12,
          display: "grid",
          gap: 10,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ fontWeight: 900 }}>Backpack</div>
          <button onClick={onClose}>Close</button>
        </div>

        {loading ? (
          <div style={{ opacity: 0.85 }}>Loading…</div>
        ) : error ? (
          <div style={{ color: "crimson" }}>{error}</div>
        ) : items.length === 0 ? (
          <div style={{ opacity: 0.85 }}>Your backpack is empty.</div>
        ) : (
          <div style={{ display: "grid", gap: 8 }}>
            {items.map((it) => (
              <div
                key={it.itemId}
                style={{
                  border: "1px solid #2f2f2f",
                  borderRadius: 10,
                  padding: 10,
                  display: "flex",
                  justifyContent: "space-between",
                  gap: 10,
                  alignItems: "center",
                }}
              >
                <div>
                  <div style={{ fontWeight: 800 }}>
                    {it.name}{" "}
                    <span style={{ opacity: 0.7, fontWeight: 600, fontSize: 12 }}>
                      • {it.rarity}
                    </span>
                  </div>
                  <div style={{ opacity: 0.75, fontSize: 12 }}>Type/slot: {it.slot}</div>
                </div>

                <button onClick={() => drop(it.itemId)}>Drop</button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
