// apps/client/src/components/MapPanel.tsx
import React, { useEffect, useMemo, useRef, useState } from "react";
import { getJson } from "../net/api";

export type Settlement = {
  id: string;
  name: string;
  type: string;
  x: number;
  y: number;
  signpost?: { x: number; y: number };
  travelFee?: number;
  tier?: number;
  prosperity?: number;
};


type POIType = "ruins" | "cave" | "enemy_camp" | "mountain_summit";

type PointOfInterest = {
  id: string;
  name: string;
  type: POIType;
  x: number;
  y: number;
  minLevel?: number;
  note?: string;
};

type World = {
  id: string;
  name: string;
  width: number;
  height: number;
  legend: Record<string, string>;
  tiles: string[];
  settlements: Settlement[];
  pointsOfInterest?: PointOfInterest[];
  namedRegions?: Array<{ name: string; x1: number; y1: number; x2: number; y2: number }>;
};

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function tileStyle(ch: string): React.CSSProperties {
  switch (ch) {
    case "w":
      return { background: "#4aa3df" };
    case "f":
      return { background: "#2f6b2f" };
    case "r":
      return { background: "#8a8a8a" };
    case "h":
      return { background: "#9c8f7a" };
    case "s":
      return { background: "#6f6f6f" };
    default:
      return { background: "#7ecf7a" };
  }
}

function isWalkable(_ch: string) {
  return true;
}

const POI_ICON: Record<POIType, string> = {
  ruins: "🏚️",
  cave: "🕳️",
  enemy_camp: "⛺",
  mountain_summit: "🐉",
};

const POI_LABEL: Record<POIType, string> = {
  ruins: "ruins",
  cave: "cave",
  enemy_camp: "enemy camp",
  mountain_summit: "dragon summit",
};

const POI_RING: Record<POIType, string> = {
  ruins: "rgba(196, 155, 92, 0.85)",
  cave: "rgba(90, 160, 210, 0.85)",
  enemy_camp: "rgba(210, 80, 80, 0.9)",
  mountain_summit: "rgba(160, 90, 210, 0.9)",
};

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
  onWorldLoaded?: (meta: { width: number; height: number; regionId: string; settlements: Settlement[] }) => void;
}) {
  const [world, setWorld] = useState<World | null>(null);
  const [error, setError] = useState("");
  const [hoverInfo, setHoverInfo] = useState("");

  const containerRef = useRef<HTMLDivElement | null>(null);

  const onWorldLoadedRef = useRef(onWorldLoaded);
  useEffect(() => {
    onWorldLoadedRef.current = onWorldLoaded;
  }, [onWorldLoaded]);

  // Viewport
  const VIEW_W = 31;
  const VIEW_H = 19;
  const halfW = Math.floor(VIEW_W / 2);
  const halfH = Math.floor(VIEW_H / 2);

  // Fixed visual sizing (tight + no scrollbars)
  const TILE = 22; // tweak: 18–22 looks great
  const GAP = 1;
  const RADIUS = 4;

  // Exact pixel size of the grid area
  const GRID_W_PX = VIEW_W * TILE + (VIEW_W - 1) * GAP;
  const GRID_H_PX = VIEW_H * TILE + (VIEW_H - 1) * GAP;

  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        setError("");

        const data = await getJson<World>(`/world/regions/${regionId}`);
        if (cancelled) return;

        const inferredHeight = Array.isArray(data.tiles) ? data.tiles.length : 0;
        const inferredWidth =
          inferredHeight > 0 && typeof data.tiles[0] === "string" ? data.tiles[0].length : 0;

        const width = Number((data as any).width ?? inferredWidth);
        const height = Number((data as any).height ?? inferredHeight);

        const normalized: World = {
          ...data,
          width,
          height,
          settlements: Array.isArray((data as any).settlements) ? (data as any).settlements : [],
          pointsOfInterest: Array.isArray((data as any).pointsOfInterest) ? (data as any).pointsOfInterest : [],
        };

        setWorld(normalized);

        onWorldLoadedRef.current?.({
          width,
          height,
          regionId,
          settlements: normalized.settlements ?? [],
        });
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
    const map = new Map<string, Settlement>();
    if (!world) return map;

    for (const s of world.settlements || []) {
      map.set(`${s.x},${s.y}`, s);
      if (s.signpost) map.set(`${s.signpost.x},${s.signpost.y}`, s);
    }
    return map;
  }, [world]);

  const poiByCoord = useMemo(() => {
    const map = new Map<string, PointOfInterest>();
    if (!world) return map;

    for (const p of world.pointsOfInterest || []) {
      map.set(`${p.x},${p.y}`, p);
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

    const step = dx !== 0 ? { dx, dy: 0 } : { dx: 0, dy };
    tryStep(step.dx, step.dy);
  }

  function tileLabel(ch: string) {
    const name = world?.legend?.[ch];
    return name || "grass";
  }

  function describePoi(p: PointOfInterest) {
    const lvl = typeof p.minLevel === "number" ? ` • Min Lv ${p.minLevel}` : "";
    const note = p.note ? ` • ${p.note}` : "";
    return `${POI_ICON[p.type]} ${p.name} • ${POI_LABEL[p.type]}${lvl}${note}`;
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
        gridTemplateRows: "auto auto auto",
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

      {/* Fixed map canvas: no inner scrolling */}
      <div style={{ display: "grid", gap: 8 }}>
        <div
          style={{
            width: GRID_W_PX,
            height: GRID_H_PX,
            overflow: "hidden",
            border: "1px solid rgba(0,0,0,0.25)",
            borderRadius: 10,
            padding: 6,
            boxSizing: "border-box",
            background: "rgba(0,0,0,0.03)",
          }}
        >
          <div
            style={{
              display: "grid",
              gridTemplateColumns: `repeat(${VIEW_W}, ${TILE}px)`,
              gridTemplateRows: `repeat(${VIEW_H}, ${TILE}px)`,
              gap: GAP,
              alignContent: "start",
              userSelect: "none",
            }}
          >
            {view.cells.map(({ gx, gy, ch }) => {
              const isPlayer = gx === x && gy === y;
              const settlement = settlementByCoord.get(`${gx},${gy}`);
              const poi = poiByCoord.get(`${gx},${gy}`);

              const base = tileStyle(ch);
              const border = isPlayer ? "2px solid #111" : "1px solid rgba(0,0,0,0.15)";
              const poiRing = poi ? `inset 0 0 0 2px ${POI_RING[poi.type]}` : "none";
              const icon = isPlayer ? "⚔️" : settlement ? "📍" : poi ? POI_ICON[poi.type] : "";

              return (
                <button
                  key={`${gx},${gy}`}
                  onMouseEnter={() => {
                    if (settlement) {
                      setHoverInfo(
                        `${settlement.name} • ${settlement.type}` +
                        (settlement.tier ? ` • Tier ${settlement.tier}` : "") +
                        (typeof settlement.prosperity === "number" ? ` • Prosperity ${settlement.prosperity}` : "") +
                        (settlement.travelFee ? ` • Cart Fee: ${settlement.travelFee}g` : "")
                      );
                      return;
                    }
                    if (poi) {
                      setHoverInfo(describePoi(poi));
                      return;
                    }
                    setHoverInfo(`${tileLabel(ch)} • (${gx},${gy})`);
                  }}
                  onMouseLeave={() => setHoverInfo("")}
                  onClick={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    focusMap();
                    clickCell(gx, gy);
                  }}
                  style={{
                    width: TILE,
                    height: TILE,
                    padding: 0,
                    border,
                    borderRadius: RADIUS,
                    cursor: "pointer",
                    ...base,
                    boxShadow: poiRing,
                    display: "grid",
                    placeItems: "center",
                    fontSize: 12,
                    fontWeight: 900,
                  }}
                  title={`${gx},${gy}`}
                >
                  {icon}
                </button>
              );
            })}
          </div>
        </div>

        <div style={{ display: "flex", justifyContent: "space-between", opacity: 0.85, fontSize: 12 }}>
          <div>
            Legend: <b>⚔️</b> you • <b>📍</b> settlement • <b>🏚️</b> ruins • <b>🕳️</b> cave •{" "}
            <b>⛺</b> enemy camp • <b>🐉</b> dragon summit
          </div>
          <div>
            Viewport: {VIEW_W}×{VIEW_H} • World: {world.width}×{world.height}
          </div>
        </div>
      </div>
    </div>
  );
}
