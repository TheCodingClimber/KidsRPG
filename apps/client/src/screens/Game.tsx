import { useEffect, useState } from "react";
import { getJson, postJson } from "../net/api";
import ChatPanel from "../components/ChatPanel";
import MapPanel from "../components/MapPanel";
import EquipmentPanel from "../components/EquipmentPanel";
import BackpackModal from "../components/BackpackModal";
import TravelModal from "../components/TravelModal";
import { fastTravel } from "../net/api";

const [travelOpen, setTravelOpen] = useState(false);
const [settlements, setSettlements] = useState<any[]>([]);
<button onClick={() => setTravelOpen(true)}>Fast Travel</button>


type LoadedGame = {
  character: { id: string; name: string; level: number; gold: number };
  save: { region_id: string; x: number; y: number; state_json?: string };
};

type ChatMsg = {
  id: string;
  from: "dm" | "player" | "system";
  text: string;
  ts: number;
};

const STARTER_KITS: Record<string, string[]> = {
  wanderer: ["Bedroll", "Rope (50ft)", "Torch (3)", "Trail Rations (3)"],
  town: ["Map of the Hearthlands", "Copper Key (mystery)", "Bread (2)", "Small Bandage Kit"],
  hunter: ["Hunting Knife", "Snare Wire", "Torch (1)", "Jerky (4)"],
  scholar: ["Notebook & Quill", "Ink Vial", "Tiny Rune Charm", "Tea Leaves (3)"],
  bruiser: ["Training Gloves", "Whetstone", "Small Healing Potion", "Jerky (2)"],
};

const [worldMeta, setWorldMeta] = useState<{ width: number; height: number; regionId: string } | null>(null);


function safeParseState(state_json: any): any {
  if (!state_json || typeof state_json !== "string") return {};
  try {
    return JSON.parse(state_json);
  } catch {
    return {};
  }
}

export function Game({ characterId }: { characterId: string }) {
  const [game, setGame] = useState<LoadedGame | null>(null);
  const [error, setError] = useState("");

  const [chat, setChat] = useState<ChatMsg[]>(() => [
    {
      id: "welcome",
      from: "dm",
      text: "Welcome, adventurer. The hearth is warm, the ale is cold, and the road is hungry. What do you do?",
      ts: Date.now(),
    },
  ]);
  const [input, setInput] = useState("");

  const [showBackpack, setShowBackpack] = useState(false);
  const [backpackItems, setBackpackItems] = useState<string[]>([]);

  useEffect(() => {
    (async () => {
      try {
        const data = await getJson<LoadedGame>(`/game/load/${characterId}`);
        setGame(data);

        const state = safeParseState(data.save?.state_json);
        const kitId = state?.starterKitId as string | undefined;
        const kitItems = kitId ? STARTER_KITS[kitId] : undefined;
        setBackpackItems(kitItems ? [...kitItems] : ["Bread (2)", "Torch (3)"]);
      } catch (e: any) {
        setError(e.message || "Failed to load game");
      }
    })();
  }, [characterId]);

  async function savePos(regionId: string, x: number, y: number) {
    await postJson(`/game/save-position/${characterId}`, { regionId, x, y });
  }

async function move(dx: number, dy: number) {
  if (!game) return;

  const meta = worldMeta;
  if (!meta || meta.regionId !== game.save.region_id) {
    // If world size isn't known yet, just block movement for safety
    setChat((prev) => [
      ...prev,
      { id: `sys_${Date.now()}`, from: "system", text: "Map not ready yet.", ts: Date.now() },
    ]);
    return;
  }

  const nx = game.save.x + dx;
  const ny = game.save.y + dy;

  // Block walking off-map
  if (nx < 0 || ny < 0 || nx >= meta.width || ny >= meta.height) {
    setChat((prev) => [
      ...prev,
      { id: `sys_${Date.now()}`, from: "system", text: "You can't go that way.", ts: Date.now() },
    ]);
    return;
  }

  const next = { ...game, save: { ...game.save, x: nx, y: ny } };
  setGame(next);

  await savePos(next.save.region_id, nx, ny);

  setChat((prev) => [
    ...prev,
    {
      id: `step_${Date.now()}`,
      from: "system",
      text: `Moved to (${nx}, ${ny}) in ${next.save.region_id}.`,
      ts: Date.now(),
    },
  ]);
}


  function send() {
    const text = input.trim();
    if (!text) return;

    setChat((prev) => [
      ...prev,
      { id: `p_${Date.now()}`, from: "player", text, ts: Date.now() },
      {
        id: `dm_${Date.now() + 1}`,
        from: "dm",
        text: "Noted. (AI DM hookup is next. This is a placeholder response.)",
        ts: Date.now(),
      },
    ]);

    setInput("");
  }

  if (error) return <div style={{ padding: 24, color: "crimson" }}>{error}</div>;
  if (!game) return <div style={{ padding: 24 }}>Loading…</div>;

  return (
    <div
      style={{
        height: "100vh",
        display: "grid",
        // Chat is intentionally shorter now, map gets the bottom space
        gridTemplateRows: "38vh auto 1fr",
        gap: 10,
        padding: 10,
        boxSizing: "border-box",
      }}
    >
      {/* Row 1: Chat (shorter) */}
      <div style={{ minHeight: 0 }}>
        <ChatPanel
          title={`${game.character.name} • Lv ${game.character.level} • ${game.character.gold}g • Region: ${game.save.region_id}`}
          messages={chat}
        />
      </div>

      {/* Row 2: Input */}
      <div
        style={{
          border: "1px solid #333",
          borderRadius: 10,
          padding: 10,
          display: "grid",
          gridTemplateColumns: "1fr auto auto",
          gap: 8,
          alignItems: "center",
        }}
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") send();
          }}
          placeholder="Type what you do…"
          style={{ padding: 10 }}
        />
        <button onClick={send}>Send</button>
        <button onClick={() => setShowBackpack(true)}>Backpack</button>
      </div>

      {/* Row 3: Bottom area (map + equipment) */}
      <div
        style={{
          minHeight: 0,
          display: "grid",
          gridTemplateColumns: "1fr 420px",
          gap: 10,
        }}
      >
        {/* Map gets the big left space */}
        <div style={{ minHeight: 0 }}>
          <MapPanel
            regionId={game.save.region_id}
            x={game.save.x}
            y={game.save.y}
            onMove={move}
            onWorldLoaded={(meta: any) => {
            setWorldMeta(meta);
            setSettlements(meta.settlements ?? []);
        }}
        />

        </div>

        {/* Equipment on the right */}
        <div style={{ minHeight: 0 }}>
          <EquipmentPanel />
        </div>
      </div>

      <TravelModal
        open={travelOpen}
        onClose={() => setTravelOpen(false)}
        settlements={settlements}
        regionId={game.save.region_id}
        playerX={game.save.x}
        playerY={game.save.y}
        gold={game.character.gold}
        onTravel={async (settlementId) => {
        const r = await fastTravel(game.character.id, game.save.region_id, settlementId);

    // update local state with returned save + gold
    setGame((prev: any) => ({
      ...prev,
      character: { ...prev.character, gold: r.character.gold },
      save: r.save,
    }));

    setChat((prev: any) => [
      ...prev,
      { id: `sys_${Date.now()}`, from: "system", text: `Traveled to ${r.settlementName} (-${r.fee}g).`, ts: Date.now() },
    ]);

    setTravelOpen(false);
  }}
/>


      <BackpackModal
        open={showBackpack}
        onClose={() => setShowBackpack(false)}
        items={backpackItems}
        onDropItem={(idx) => {
          setBackpackItems((prev) => prev.filter((_, i) => i !== idx));
        }}
      />
    </div>
  );
}
