import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import ChatPanel from "../components/ChatPanel";
import MapPanel, { Settlement } from "../components/MapPanel";
import EquipmentPanel from "../components/EquipmentPanel";
import BackpackModal from "../components/BackpackModal";
import TravelModal from "../components/TravelModal";
import StatusPanel from "../components/StatusPanel";

import { getJson, postJson } from "../net/api";

type LoadedGame = {
  character: {
    id: string;
    name: string;
    race: string;
    class: string;
    background: string;
    personality: number;
    level: number;
    gold: number;
  };
  save: {
    region_id: string;
    x: number;
    y: number;
    last_seen_at: number;
    state_json: string;
  };
};

type ChatMsg = {
  id: string;
  from: "system" | "player" | "npc";
  text: string;
  ts: number;
};

async function fastTravel(characterId: string, regionId: string, settlementId: string) {
  return postJson<{
    ok: boolean;
    fee: number;
    settlementName: string;
    character: { id: string; gold: number };
    save: { region_id: string; x: number; y: number; last_seen_at: number; state_json: string };
  }>(`/game/fast-travel/${characterId}`, { regionId, settlementId });
}

async function savePosition(characterId: string, regionId: string, x: number, y: number) {
  return postJson<{ ok: boolean }>(`/game/save-position/${characterId}`, { regionId, x, y });
}

function safeJsonParse(s: string) {
  try {
    return JSON.parse(s);
  } catch {
    return {};
  }
}

export default function Game({
  characterId,
  onExitToMenu,
}: {
  characterId: string;
  onExitToMenu: () => void;
}) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [game, setGame] = useState<LoadedGame | null>(null);

  const [chat, setChat] = useState<ChatMsg[]>([
    {
      id: `sys_${Date.now()}`,
      from: "system",
      text: "Welcome, adventurer. (AI DM comes soon.) For now: explore, fast travel, and we’ll add encounters next.",
      ts: Date.now(),
    },
  ]);

  const [inputText, setInputText] = useState("");

  const [backpackOpen, setBackpackOpen] = useState(false);

  // Travel state
  const [travelOpen, setTravelOpen] = useState(false);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [worldMeta, setWorldMeta] = useState<{ width: number; height: number; regionId: string } | null>(
    null
  );

  // Prevent spammy save calls (basic debounce)
  const saveTimerRef = useRef<number | null>(null);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        setError("");
        setLoading(true);

        const data = await getJson<LoadedGame>(`/game/load/${characterId}`);
        if (cancelled) return;

        setGame(data);

        setChat((prev) => [
          ...prev,
          {
            id: `sys_load_${Date.now()}`,
            from: "system",
            text: `Loaded ${data.character.name} at (${data.save.x},${data.save.y}) in ${data.save.region_id}.`,
            ts: Date.now(),
          },
        ]);
      } catch (e: any) {
        if (cancelled) return;
        setError(e.message || "Failed to load game");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [characterId]);

  const state = useMemo(() => safeJsonParse(game?.save.state_json || "{}"), [game?.save.state_json]);

  // Charm display (safe fallbacks until DB/state is fully wired)
  const charmName: string = state?.charmName || state?.charmId || "Lucky Charm";
  const charmPerk: string =
    state?.charmPerk ||
    "A tiny blessing that nudges luck during events/rolls later.";

  const objectives: string[] = Array.isArray(state?.objectives)
    ? state.objectives
    : [
        "Visit a settlement and look for rumors.",
        "Explore a cave or ruin and mark it on your map.",
        "Train up for the dragon summit (high level).",
      ];

  // Basic placeholder stats (until you add them to DB/state)
  const hpMax = Number(state?.hpMax ?? 10);
  const hp = Number(state?.hp ?? hpMax);
  const staminaMax = Number(state?.staminaMax ?? 10);
  const stamina = Number(state?.stamina ?? staminaMax);

  const handleWorldLoaded = useCallback((meta: any) => {
    setWorldMeta({ width: meta.width, height: meta.height, regionId: meta.regionId });
    setSettlements(meta.settlements ?? []);
  }, []);

  function scheduleSave(regionId: string, x: number, y: number) {
    if (!game) return;

    if (saveTimerRef.current) {
      window.clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;
    }

    saveTimerRef.current = window.setTimeout(async () => {
      try {
        await savePosition(game.character.id, regionId, x, y);
      } catch {
        // ignore
      }
    }, 250);
  }

  function move(dx: number, dy: number) {
    if (!game) return;

    const nx = game.save.x + dx;
    const ny = game.save.y + dy;

    setGame((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        save: {
          ...prev.save,
          x: nx,
          y: ny,
          last_seen_at: Date.now(),
        },
      };
    });

    setChat((prev) => [
      ...prev,
      { id: `sys_move_${Date.now()}`, from: "system", text: `Moved to (${nx},${ny}).`, ts: Date.now() },
    ]);

    scheduleSave(game.save.region_id, nx, ny);
  }

  function sendPlayerText() {
    const trimmed = inputText.trim();
    if (!trimmed) return;

    setChat((prev) => [
      ...prev,
      { id: `p_${Date.now()}`, from: "player", text: trimmed, ts: Date.now() },
      {
        id: `sys_${Date.now() + 1}`,
        from: "system",
        text: "DM is sleeping (AI coming soon). Next: encounters + dice log.",
        ts: Date.now(),
      },
    ]);

    setInputText("");
  }

  async function handleFastTravel(settlementId: string) {
    if (!game) return;

    try {
      const regionId = game.save.region_id;
      const r = await fastTravel(game.character.id, regionId, settlementId);

      setGame((prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          character: { ...prev.character, gold: r.character.gold },
          save: r.save,
        };
      });

      setChat((prev) => [
        ...prev,
        {
          id: `sys_travel_${Date.now()}`,
          from: "system",
          text: `Traveled to ${r.settlementName} (-${r.fee}g).`,
          ts: Date.now(),
        },
      ]);

      setTravelOpen(false);
    } catch (e: any) {
      setChat((prev) => [
        ...prev,
        {
          id: `sys_travel_fail_${Date.now()}`,
          from: "system",
          text: `Fast travel failed: ${e?.message || "unknown error"}`,
          ts: Date.now(),
        },
      ]);
    }
  }

  function logout() {
    localStorage.removeItem("sessionId");
    localStorage.removeItem("accountId");
    location.reload();
  }

  if (loading) return <div style={{ padding: 18 }}>Loading…</div>;

  if (error) {
    return (
      <div style={{ padding: 18 }}>
        <div style={{ color: "crimson", marginBottom: 10 }}>{error}</div>
        <button onClick={onExitToMenu}>Back to Menu</button>
      </div>
    );
  }

  if (!game) {
    return (
      <div style={{ padding: 18 }}>
        <div style={{ marginBottom: 10 }}>No game loaded.</div>
        <button onClick={onExitToMenu}>Back to Menu</button>
      </div>
    );
  }

  return (
    <div
      style={{
        height: "100vh",
        display: "grid",
        gridTemplateRows: "52px 1fr auto 420px", // topbar, chatlog, input, bottom row
        background: "white",
        color: "black",
        minHeight: 0,
      }}
    >
      {/* Top bar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "10px 12px",
          borderBottom: "1px solid #222",
        }}
      >
        <div style={{ fontWeight: 900 }}>
          {game.character.name}{" "}
          <span style={{ opacity: 0.7, fontWeight: 600 }}>
            Lv{game.character.level} • {game.character.gold}g
          </span>
        </div>

        <div style={{ marginLeft: "auto", display: "flex", gap: 8 }}>
          <button onClick={() => setTravelOpen(true)}>Fast Travel</button>
          <button onClick={() => setBackpackOpen(true)}>Backpack</button>
          <button onClick={onExitToMenu}>Menu</button>
          <button onClick={logout}>Logout</button>
        </div>
      </div>

      {/* Row 1: System/Chat log (full width) */}
      <div style={{ padding: 10, minHeight: 0 }}>
        <ChatPanel
          messages={chat}
          // IMPORTANT: we’re using the dedicated input row below.
          // If your ChatPanel still renders its own input, we’ll remove it next.
          onSend={() => {}}
        />
      </div>

      {/* Row 2: Player input row (full width) */}
      <div
        style={{
          padding: "0 10px 10px",
          display: "flex",
          gap: 10,
          alignItems: "center",
        }}
      >
        <input
          value={inputText}
          onChange={(e) => setInputText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") sendPlayerText();
          }}
          placeholder="What do you do?"
          style={{
            flex: 1,
            padding: "10px 12px",
            borderRadius: 10,
            border: "1px solid #333",
            background: "white",
            color: "black",
            outline: "none",
          }}
        />
        <button onClick={sendPlayerText} style={{ padding: "10px 14px" }}>
          Send
        </button>
      </div>

      {/* Row 3: Map (left) + Status (middle) + Equipment (right) */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 2fr 420px"
,
          gap: 10,
          padding: 10,
          minHeight: 0,
        }}
      >
        {/* Map */}
        <div style={{ minHeight: 0 }}>
          <MapPanel
            regionId={game.save.region_id}
            x={game.save.x}
            y={game.save.y}
            onMove={move}
            onWorldLoaded={handleWorldLoaded}
          />
        </div>

        {/* Status panel */}
        <div style={{ minHeight: 0 }}>
          <StatusPanel
            name={game.character.name}
            cls={game.character.class}
            level={game.character.level}
            hp={hp}
            hpMax={hpMax}
            stamina={stamina}
            staminaMax={staminaMax}
            gold={game.character.gold}
            charmName={charmName}
            charmPerk={charmPerk}
            objectives={objectives}
          />
        </div>

        {/* Equipment */}
        <div style={{ minHeight: 0, display: "grid", gridTemplateRows: "auto 1fr", gap: 10 }}>
          {/* Equipment header w/ Backpack button */}
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ fontWeight: 800, opacity: 0.9 }}>Equipment</div>
            <button onClick={() => setBackpackOpen(true)}>Backpack</button>
          </div>

          <EquipmentPanel characterId={game.character.id} onOpenBackpack={() => setBackpackOpen(true)} />
        </div>
      </div>

      {/* Modals */}
      <BackpackModal
        open={backpackOpen}
        onClose={() => setBackpackOpen(false)}
        characterId={game.character.id}
      />

      <TravelModal
        open={travelOpen}
        onClose={() => setTravelOpen(false)}
        settlements={settlements}
        regionId={game.save.region_id}
        playerX={game.save.x}
        playerY={game.save.y}
        gold={game.character.gold}
        onTravel={handleFastTravel}
      />
    </div>
  );
}
