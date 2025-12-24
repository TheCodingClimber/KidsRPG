export default function BackpackModal({
  open,
  onClose,
  items,
  onDropItem,
}: {
  open: boolean;
  onClose: () => void;
  items: string[];
  onDropItem: (idx: number) => void;
}) {
  if (!open) return null;

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.4)",
        display: "grid",
        placeItems: "center",
        padding: 12,
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: "min(560px, 95vw)",
          maxHeight: "80vh",
          overflow: "auto",
          background: "white",
          borderRadius: 12,
          border: "1px solid #333",
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

        {items.length === 0 ? (
          <div style={{ opacity: 0.8 }}>Your backpack is empty.</div>
        ) : (
          <div style={{ display: "grid", gap: 8 }}>
            {items.map((it, idx) => (
              <div
                key={`${it}_${idx}`}
                style={{
                  border: "1px solid #444",
                  borderRadius: 10,
                  padding: 10,
                  display: "flex",
                  justifyContent: "space-between",
                  gap: 10,
                }}
              >
                <div>{it}</div>
                <button onClick={() => onDropItem(idx)}>Drop</button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
