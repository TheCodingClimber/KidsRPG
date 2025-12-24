export default function Menu({
  onSelect,
  onLogout,
}: {
  onSelect: (s: string) => void;
  onLogout: () => void;
}) {
  return (
    <div style={{ padding: 24, display: "grid", gap: 12, maxWidth: 360 }}>
      <h2>KidsRPG</h2>

      <button onClick={() => onSelect("new")}>New Game</button>
      <button onClick={() => onSelect("load")}>Load Game</button>
      <button onClick={() => onSelect("create")}>Create Character</button>

    <br/>
      <button onClick={onLogout} style={{ opacity: 0.7 }}>
        Log out
      </button>
    </div>
  );
}
