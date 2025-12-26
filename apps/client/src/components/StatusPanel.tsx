// apps/client/src/components/StatusPanel.tsx
import React, { useMemo } from "react";

type StatusPanelProps = {
  name: string;
  cls: string;
  level: number;
  hp: number;
  hpMax: number;
  stamina: number;
  staminaMax: number;
  gold: number;

  charmName?: string;
  charmPerk?: string;

  objectives?: string[]; // simple list for now
};

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function barPct(value: number, max: number) {
  if (!max || max <= 0) return 0;
  return clamp((value / max) * 100, 0, 100);
}

export default function StatusPanel(props: StatusPanelProps) {
  const hpPct = useMemo(() => barPct(props.hp, props.hpMax), [props.hp, props.hpMax]);
  const stPct = useMemo(
    () => barPct(props.stamina, props.staminaMax),
    [props.stamina, props.staminaMax]
  );

  const objectives = props.objectives ?? [];

  return (
    <div
      style={{
        height: "100%",
        border: "1px solid #333",
        borderRadius: 10,
        padding: 12,
        boxSizing: "border-box",
        display: "grid",
        gridTemplateRows: "auto auto auto 1fr",
        gap: 10,
        background: "rgba(0,0,0,0.03)",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "baseline" }}>
        <div style={{ fontWeight: 900, fontSize: 16 }}>
          {props.name}
        </div>
        <div style={{ opacity: 0.8, fontWeight: 700 }}>
          {props.cls} • Lv {props.level}
        </div>
      </div>

      {/* HP / Stamina */}
      <div style={{ display: "grid", gap: 8 }}>
        <div style={{ display: "grid", gap: 6 }}>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, opacity: 0.9 }}>
            <div style={{ fontWeight: 800 }}>HP</div>
            <div>
              {props.hp}/{props.hpMax}
            </div>
          </div>
          <div
            style={{
              height: 12,
              borderRadius: 999,
              border: "1px solid rgba(0,0,0,0.35)",
              background: "rgba(0,0,0,0.10)",
              overflow: "hidden",
            }}
            title="Hit Points"
          >
            <div
              style={{
                width: `${hpPct}%`,
                height: "100%",
                background: "linear-gradient(90deg, rgba(180,30,30,0.95), rgba(230,80,80,0.95))",
              }}
            />
          </div>
        </div>

        <div style={{ display: "grid", gap: 6 }}>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, opacity: 0.9 }}>
            <div style={{ fontWeight: 800 }}>Stamina</div>
            <div>
              {props.stamina}/{props.staminaMax}
            </div>
          </div>
          <div
            style={{
              height: 12,
              borderRadius: 999,
              border: "1px solid rgba(0,0,0,0.35)",
              background: "rgba(0,0,0,0.10)",
              overflow: "hidden",
            }}
            title="Stamina"
          >
            <div
              style={{
                width: `${stPct}%`,
                height: "100%",
                background: "linear-gradient(90deg, rgba(30,120,40,0.95), rgba(90,200,110,0.95))",
              }}
            />
          </div>
        </div>
      </div>

      {/* Gold + Charm */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 10,
          alignItems: "start",
        }}
      >
        <div
          style={{
            border: "1px solid rgba(0,0,0,0.20)",
            borderRadius: 10,
            padding: 10,
            background: "rgba(255,255,255,0.55)",
          }}
        >
          <div style={{ fontWeight: 900 }}>Gold</div>
          <div style={{ fontSize: 20, fontWeight: 900, letterSpacing: 0.5 }}>{props.gold}g</div>
        </div>

        <div
          style={{
            border: "1px solid rgba(0,0,0,0.20)",
            borderRadius: 10,
            padding: 10,
            background: "rgba(255,255,255,0.55)",
            minHeight: 64,
          }}
        >
          <div style={{ fontWeight: 900 }}>Lucky Charm</div>
          <div style={{ opacity: 0.9, fontWeight: 800 }}>
            {props.charmName || "(none)"}
          </div>
          <div style={{ opacity: 0.75, fontSize: 12, marginTop: 4 }}>
            {props.charmPerk || "Perk will apply to events/rolls later."}
          </div>
        </div>
      </div>

      {/* Objectives */}
      <div
        style={{
          border: "1px solid rgba(0,0,0,0.20)",
          borderRadius: 10,
          padding: 10,
          background: "rgba(255,255,255,0.55)",
          overflow: "hidden",
          minHeight: 0,
          display: "grid",
          gridTemplateRows: "auto 1fr",
          gap: 8,
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <div style={{ fontWeight: 900 }}>Objectives</div>
          <div style={{ fontSize: 12, opacity: 0.7 }}>
            {objectives.length ? `${objectives.length} active` : "none"}
          </div>
        </div>

        {objectives.length === 0 ? (
          <div style={{ opacity: 0.75, fontSize: 13 }}>
            No active objectives yet. Explore, visit settlements, and poke suspicious ruins.
          </div>
        ) : (
          <ul style={{ margin: 0, paddingLeft: 18, display: "grid", gap: 6, overflow: "auto" }}>
            {objectives.map((o, idx) => (
              <li key={`${idx}_${o}`} style={{ lineHeight: 1.35 }}>
                {o}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
