import { useEffect, useMemo, useRef, useState } from "react";
import { getJson } from "../net/api";

type Settlement = {
  id: string;
  name: string;
  type: "town" | "village";
  x: number;
  y: number;
  signpost?: { x: number; y: number };
  travelFee?: number;
};


type World = {
  id: string;
  name: string;
  width: number;
  height: number;
  legend: Record<string, string>;
  tiles: string[]; // array of strings, each string is a row
  settlements: Array<{
    id: string;
    name: string;
    type: "town" | "village";
    x: number;
    y: number;
    signpost?: { x: number; y: number };
    travelFee?: number;
  }>;
  namedRegions?: Array<{ name: string; x1: number; y1: number; x2: number; y2: number }>;
};

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function tileStyle(ch: string): React.CSSProperties {
  switch (ch) {
    case "w": // water
      return { background: "#4aa3df" };
    case "f": // forest
      return { background: "#2f6b2f" };
    case "r": // road
      return { background: "#8a8a8a" };
    case "h": // hills
      return { background: "#9c8f7a" };
    case "s": // stone
      return { background: "#6f6f6f" };
    default: // grass
      return { background: "#7ecf7a" };
  }
}


function isWalkable(_ch: string) {
  return true; // v1: everything walkable
}

export default function MapPanel({
  regionId,
  x,
  y,
  onMove,
  onWorldLoaded,
}: {
  regionId: string;
  x: number;
  y: number;
  onMove: (dx: number, dy: number) => void;
  onWorldLoaded?: (meta: { width: number; height: number; regionId: string }) => void;
}) {
  const [world, setWorld] = useState<World | null>(null);
  const [error, setError] = useState("");
  const [hoverInfo, setHoverInfo] = useState("");

  const containerRef = useRef<HTMLDivElement | null>(null);

  // Viewport size
  const VIEW_W = 31;
  const VIEW_H = 19;
  const halfW = Math.floor(VIEW_W / 2);
  const halfH = Math.floor(VIEW_H / 2);

  useEffect(() => {
  let cancelled = false;

  (async () => {
    try {
      setError("");

      const data = await getJson<World>(`/world/regions/${regionId}`);
      if (cancelled) return;

      // Infer bounds from tiles if width/height are missing
      const inferredHeight = Array.isArray(data.tiles) ? data.tiles.length : 0;
      const inferredWidth =
        inferredHeight > 0 && typeof data.tiles[0] === "string"
          ? data.tiles[0].length
          : 0;

      const width = Number(data.width ?? inferredWidth);
      const height = Number(data.height ?? inferredHeight);

      const normalized: World = {
        ...data,
        width,
        height,
      };

      setWorld(normalized);

      onWorldLoaded?.({ 
        width, 
        height, 
        regionId,
        settlements: normalized.settlements ?? [],
     });

      console.log("World loaded:", { width, height, inferredWidth, inferredHeight });
    } catch (e: any) {
      if (!cancelled) setError(e.message || "Failed to load world");
    }
  })();

  return () => {
    cancelled = true;
  };
}, [regionId]);



  function focusMap() {
    containerRef.current?.focus();
  }

  function tryStep(dx: number, dy: number) {
  if (!world) return;

  const nx = x + dx;
  const ny = y + dy;

  // HARD BOUNDS CHECK
  if (nx < 0 || ny < 0 || nx >= world.width || ny >= world.height) {
    setHoverInfo("Edge of the world. You can't go that way.");
    return;
  }

  const ch = world.tiles[ny]?.[nx] ?? ".";
  if (!isWalkable(ch)) {
    setHoverInfo("That way is blocked.");
    return;
  }

  onMove(dx, dy);
}


  function onKeyDown(e: React.KeyboardEvent) {
  const key = e.key.toLowerCase();
  if (key === "arrowup" || key === "w") {
    e.preventDefault();
    tryStep(0, -1);
  } else if (key === "arrowdown" || key === "s") {
    e.preventDefault();
    tryStep(0, 1);
  } else if (key === "arrowleft" || key === "a") {
    e.preventDefault();
    tryStep(-1, 0);
  } else if (key === "arrowright" || key === "d") {
    e.preventDefault();
    tryStep(1, 0);
  }
}


  const settlementByCoord = useMemo(() => {
    const map = new Map<string, World["settlements"][number]>();
    if (!world) return map;

    for (const s of world.settlements || []) {
      map.set(`${s.x},${s.y}`, s);
      if (s.signpost) map.set(`${s.signpost.x},${s.signpost.y}`, s);
    }
    return map;
  }, [world]);

  const regionName = useMemo(() => {
    if (!world?.namedRegions) return "";
    for (const r of world.namedRegions) {
      if (x >= r.x1 && x <= r.x2 && y >= r.y1 && y <= r.y2) return r.name;
    }
    return "";
  }, [world, x, y]);

  const view = useMemo(() => {
    if (!world) return null;

    const startX = clamp(x - halfW, 0, Math.max(0, world.width - VIEW_W));
    const startY = clamp(y - halfH, 0, Math.max(0, world.height - VIEW_H));

    const cells: Array<{ gx: number; gy: number; ch: string }> = [];

    for (let row = 0; row < VIEW_H; row++) {
      const gy = startY + row;
      const line = world.tiles[gy] || "";
      for (let col = 0; col < VIEW_W; col++) {
        const gx = startX + col;
        const ch = line[gx] ?? ".";
        cells.push({ gx, gy, ch });
      }
    }

    return { startX, startY, cells };
  }, [world, x, y]);

  function clickCell(gx: number, gy: number) {
    if (!world) return;

    const dx = gx === x ? 0 : gx > x ? 1 : -1;
    const dy = gy === y ? 0 : gy > y ? 1 : -1;

    // prefer horizontal if diagonal chosen
    const step = dx !== 0 ? { dx, dy: 0 } : { dx: 0, dy };

    const nx = x + step.dx;
    const ny = y + step.dy;

    const nextCh = world.tiles[ny]?.[nx] ?? ".";
    if (!isWalkable(nextCh)) return;

    tryStep(step.dx, step.dy);
  }

  function tileLabel(ch: string) {
    const name = world?.legend?.[ch];
    return name || "grass";
  }

  if (error) {
    return (
      <div style={{ padding: 10, border: "1px solid #333", borderRadius: 10, color: "crimson" }}>
        {error}
      </div>
    );
  }

  if (!world || !view) {
    return (
      <div style={{ padding: 10, border: "1px solid #333", borderRadius: 10 }}>
        Loading map…
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      tabIndex={0}
      onKeyDown={onKeyDown}
      onClick={focusMap}
      style={{
        height: "100%",
        border: "1px solid #333",
        borderRadius: 10,
        padding: 10,
        boxSizing: "border-box",
        outline: "none",
        display: "grid",
        gridTemplateRows: "auto auto 1fr auto",
        gap: 8,
        overflow: "hidden",
      }}
      title="Click here, then use WASD or arrow keys to move"
    >
      <div style={{ display: "flex", justifyContent: "space-between", gap: 10 }}>
        <div style={{ fontWeight: 800 }}>
          Map: {world.name}{" "}
          <span style={{ opacity: 0.65, fontWeight: 500 }}>
            ({x},{y})
          </span>
        </div>
        <div style={{ opacity: 0.75 }}>{regionName ? `Region: ${regionName}` : ""}</div>
      </div>

      <div style={{ opacity: 0.75, fontSize: 12 }}>
        {hoverInfo || "Tip: click the map, then use WASD/arrow keys. Click a tile to step toward it."}
      </div>

      <div
        style={{
            display: "grid",
            gridTemplateColumns: `repeat(${VIEW_W}, 1fr)`,
            gap: 0,
            alignContent: "start",
            userSelect: "none",
            overflow: "auto",
            minHeight: 0,
            paddingRight: 2,
        }}
      >
        {view.cells.map(({ gx, gy, ch }) => {
          const isPlayer = gx === x && gy === y;
          const settlement = settlementByCoord.get(`${gx},${gy}`);

          const base = tileStyle(ch);
          const border = isPlayer ? "2px solid #111" : "1px solid rgba(0,0,0,0.15)";

          return (
            <button
              key={`${gx},${gy}`}
              onMouseEnter={() => {
                const s = settlementByCoord.get(`${gx},${gy}`);
                const text = s
                  ? `${s.name} • ${s.type}${s.travelFee ? ` • Cart Fee: ${s.travelFee}g` : ""}`
                  : `${tileLabel(ch)} • (${gx},${gy})`;
                setHoverInfo(text);
              }}
              onMouseLeave={() => setHoverInfo("")}
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                focusMap();
                clickCell(gx, gy);
              }}
              style={{
                width: "100%",
                aspectRatio: "1 / 1",
                padding: 0,
                border,
                borderRadius: 6,
                cursor: "pointer",
                ...base,
                display: "grid",
                placeItems: "center",
                fontSize: 12,
                fontWeight: 800,
              }}
              title={`${gx},${gy}`}
            >
              {isPlayer ? "⚔️" : settlement ? "📍" : ""}
            </button>
          );
        })}
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", opacity: 0.75, fontSize: 12 }}>
        <div>
          Legend: <b>📍</b> settlement • <b>⚔️</b> you
        </div>
        <div>
          Viewport: {VIEW_W}×{VIEW_H} • World: {world.width}×{world.height}
        </div>
      </div>
    </div>
  );
}
