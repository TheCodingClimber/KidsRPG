const SLOTS = [
  "helmet",
  "torso",
  "gloves",
  "legs",
  "boots",
  "ring1",
  "ring2",
  "amulet",
  "cloak",
  "trinket",
] as const;

export default function EquipmentPanel() {
  return (
    <div
      style={{
        border: "1px solid #333",
        borderRadius: 10,
        padding: 10,
        display: "grid",
        gap: 10,
      }}
    >
      <div style={{ fontWeight: 800 }}>Equipment</div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
        {SLOTS.map((slot) => (
          <div
            key={slot}
            style={{
              border: "1px solid #444",
              borderRadius: 10,
              padding: 8,
              background: "rgba(0,0,0,0.03)",
            }}
          >
            <div style={{ fontWeight: 800, textTransform: "capitalize" }}>
              {slot}
            </div>
            <div style={{ opacity: 0.8 }}>(empty)</div>
          </div>
        ))}
      </div>

      <div style={{ opacity: 0.7, fontSize: 12 }}>
        (Next: load equipped items from DB + enforce slot types.)
      </div>
    </div>
  );
}
