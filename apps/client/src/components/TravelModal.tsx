import React from "react";
import type { Settlement } from "./MapPanel";

export default function TravelModal({
  open,
  onClose,
  settlements,
  regionId,
  playerX,
  playerY,
  onTravel,
  gold,
}: {
  open: boolean;
  onClose: () => void;
  settlements: Settlement[];
  regionId: string;
  playerX: number;
  playerY: number;
  gold: number;
  onTravel: (settlementId: string) => void;
}) {
  if (!open) return null;

  const rows = [...settlements].map((s) => {
    const dx = Math.abs((s.signpost?.x ?? s.x) - playerX);
    const dy = Math.abs((s.signpost?.y ?? s.y) - playerY);
    const dist = dx + dy; // manhattan distance
    const fee = Number(s.travelFee ?? (s.type === "town" ? 25 : 10));
    return { ...s, dist, fee };
  });

  rows.sort((a, b) => a.dist - b.dist);

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.55)",
        display: "grid",
        placeItems: "center",
        zIndex: 9999,
      }}
      onMouseDown={onClose}
    >
      <div
        style={{
          width: "min(720px, 92vw)",
          maxHeight: "80vh",
          overflow: "auto",
          background: "#111",
          border: "1px solid #333",
          borderRadius: 14,
          padding: 16,
        }}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "center" }}>
          <div style={{ fontWeight: 900, fontSize: 18 }}>Fast Travel (Cart)</div>
          <button onClick={onClose} style={{ padding: "6px 10px" }}>
            Close
          </button>
        </div>

        <div style={{ opacity: 0.8, marginTop: 6 }}>
          Region: <b>{regionId}</b> • Your gold: <b>{gold}g</b>
        </div>

        <div style={{ marginTop: 12, display: "grid", gap: 8 }}>
          {rows.map((s) => {
            const can = gold >= s.fee;
            return (
              <div
                key={s.id}
                style={{
                  border: "1px solid #2a2a2a",
                  borderRadius: 12,
                  padding: 12,
                  display: "grid",
                  gridTemplateColumns: "1fr auto",
                  gap: 10,
                  alignItems: "center",
                }}
              >
                <div>
                  <div style={{ fontWeight: 800 }}>
                    {s.name} <span style={{ opacity: 0.7 }}>• {s.type}</span>
                  </div>
                  <div style={{ opacity: 0.8, fontSize: 13 }}>
                    Distance: {s.dist} • Fee: {s.fee}g
                  </div>
                </div>

                <button
                  disabled={!can}
                  onClick={() => onTravel(s.id)}
                  style={{ padding: "8px 12px", cursor: can ? "pointer" : "not-allowed", opacity: can ? 1 : 0.5 }}
                >
                  Travel
                </button>
              </div>
            );
          })}
        </div>

        <div style={{ opacity: 0.7, fontSize: 12, marginTop: 12 }}>
          Tip: You can also travel from a settlement signpost when you’re standing on it.
        </div>
      </div>
    </div>
  );
}
