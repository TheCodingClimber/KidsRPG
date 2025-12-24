import { useMemo, useState } from "react";
import { postJson } from "../net/api";

const RACES = ["Human", "Elf", "Half-Elf", "Dwarf", "Halfling", "Orc", "Gnome"];
const CLASSES = ["Fighter", "Ranger", "Wizard", "Cleric", "Rogue", "Artificer"];
const BACKGROUNDS = ["Apothecary", "Hunter", "Scholar", "Merchant", "Soldier", "Outlander"];

const PERSONALITIES = [
  {
    id: "bold",
    label: "Bold Charger",
    value: 90,
    effects: [
      "+ Slightly better at intimidating enemies",
      "+ More likely to trigger heroic/rare events",
      "– Slightly more likely to rush into danger",
    ],
  },
  {
    id: "kind",
    label: "Kind Protector",
    value: 30,
    effects: [
      "+ NPCs are more helpful and forgiving",
      "+ Better at calming conflicts peacefully",
      "– Slightly less likely to get combat shortcuts",
    ],
  },
  {
    id: "clever",
    label: "Clever Trickster",
    value: 70,
    effects: [
      "+ Better at sneaking and finding shortcuts",
      "+ Higher chance to discover hidden loot options",
      "– NPCs may not trust you instantly",
    ],
  },
  {
    id: "wise",
    label: "Wise Planner",
    value: 50,
    effects: [
      "+ Better at solving puzzles and negotiations",
      "+ More consistent (fewer bad luck streaks)",
      "– Slightly fewer chaotic surprise events",
    ],
  },
  {
    id: "tough",
    label: "Tough Survivor",
    value: 100,
    effects: [
      "+ Slightly more HP from leveling",
      "+ Better at resisting fear/poison effects",
      "– NPCs may expect you to handle problems alone",
    ],
  },
  {
    id: "curious",
    label: "Curious Explorer",
    value: 10,
    effects: [
      "+ More random encounters (often good!)",
      "+ Better chance to meet rare creatures (gryphon/pegasus)",
      "– More likely to wander into odd situations",
    ],
  },
] as const;

// 5 starting kits. We’ll store kitId in save.state_json for now.
const STARTER_KITS = [
  {
    id: "wanderer",
    name: "Wanderer’s Pack",
    items: ["Bedroll", "Rope (50ft)", "Torch (3)", "Trail Rations (3)"],
    vibe: "For kids who want to explore everywhere.",
  },
  {
    id: "town",
    name: "Town Starter Kit",
    items: ["Map of the Hearthlands", "Copper Key (mystery)", "Bread (2)", "Small Bandage Kit"],
    vibe: "For kids who like secrets and NPCs.",
  },
  {
    id: "hunter",
    name: "Hunter’s Kit",
    items: ["Hunting Knife", "Snare Wire", "Torch (1)", "Jerky (4)"],
    vibe: "For tracking, surviving, and wilderness advantage.",
  },
  {
    id: "scholar",
    name: "Scholar’s Satchel",
    items: ["Notebook & Quill", "Ink Vial", "Tiny Rune Charm", "Tea Leaves (3)"],
    vibe: "For clever plans, puzzles, and lore.",
  },
  {
    id: "bruiser",
    name: "Bruiser’s Kit",
    items: ["Training Gloves", "Whetstone", "Small Healing Potion", "Jerky (2)"],
    vibe: "For brawlers and future dragon riders.",
  },
] as const;

export default function CreateCharacter({ onDone }: { onDone: () => void }) {
  const [name, setName] = useState("");
  const [race, setRace] = useState(RACES[0]);
  const [cls, setCls] = useState(CLASSES[0]);
  const [bg, setBg] = useState(BACKGROUNDS[0]);

  const [personalityId, setPersonalityId] =
    useState<(typeof PERSONALITIES)[number]["id"]>("bold");

  const [kitId, setKitId] =
    useState<(typeof STARTER_KITS)[number]["id"]>("wanderer");

  const [error, setError] = useState("");

  const selectedPersonality = useMemo(
    () => PERSONALITIES.find((p) => p.id === personalityId)!,
    [personalityId]
  );

  const selectedKit = useMemo(
    () => STARTER_KITS.find((k) => k.id === kitId)!,
    [kitId]
  );

  async function create() {
    setError("");
    try {
      await postJson<{ characterId: string }>("/characters", {
        name,
        race,
        class: cls,
        background: bg,
        personality: selectedPersonality.value,
        starterKitId: selectedKit.id, // NEW
      });
      onDone();
    } catch (e: any) {
      setError(e.message || "Failed");
    }
  }

  return (
    <div style={{ padding: 24, display: "grid", gap: 12, maxWidth: 860 }}>
      <h2>Create Character</h2>

      <div style={{ display: "grid", gap: 10, gridTemplateColumns: "1fr 1fr" }}>
        <label style={{ display: "grid", gap: 6 }}>
          Name
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Thragar"
          />
        </label>

        <label style={{ display: "grid", gap: 6 }}>
          Race
          <select value={race} onChange={(e) => setRace(e.target.value)}>
            {RACES.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </label>

        <label style={{ display: "grid", gap: 6 }}>
          Class
          <select value={cls} onChange={(e) => setCls(e.target.value)}>
            {CLASSES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>

        <label style={{ display: "grid", gap: 6 }}>
          Background
          <select value={bg} onChange={(e) => setBg(e.target.value)}>
            {BACKGROUNDS.map((b) => (
              <option key={b} value={b}>
                {b}
              </option>
            ))}
          </select>
        </label>
      </div>

      {/* Personality + Description */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 12,
          alignItems: "start",
        }}
      >
        <label style={{ display: "grid", gap: 6 }}>
          Personality
          <select
            value={personalityId}
            onChange={(e) =>
              setPersonalityId(
                e.target.value as (typeof PERSONALITIES)[number]["id"]
              )
            }
          >
            {PERSONALITIES.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            Personality affects NPC reactions, event style, and story flavor.
          </div>
        </label>

        <div
          style={{
            border: "1px solid #333",
            borderRadius: 10,
            padding: 12,
            background: "rgba(0,0,0,0.03)",
          }}
        >
          <div style={{ fontWeight: 800, marginBottom: 8 }}>
            {selectedPersonality.label}
          </div>
          <ul style={{ margin: 0, paddingLeft: 18, display: "grid", gap: 6 }}>
            {selectedPersonality.effects.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </div>
      </div>

      {/* Starter Kit + Description */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 12,
          alignItems: "start",
        }}
      >
        <label style={{ display: "grid", gap: 6 }}>
          Starting Items
          <select
            value={kitId}
            onChange={(e) =>
              setKitId(e.target.value as (typeof STARTER_KITS)[number]["id"])
            }
          >
            {STARTER_KITS.map((k) => (
              <option key={k.id} value={k.id}>
                {k.name}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            Pick a starter kit. It changes your early options and feel.
          </div>
        </label>

        <div
          style={{
            border: "1px solid #333",
            borderRadius: 10,
            padding: 12,
            background: "rgba(0,0,0,0.03)",
          }}
        >
          <div style={{ fontWeight: 800, marginBottom: 6 }}>
            {selectedKit.name}
          </div>
          <div style={{ opacity: 0.8, marginBottom: 10 }}>{selectedKit.vibe}</div>
          <div style={{ fontWeight: 800, marginBottom: 6 }}>Items</div>
          <ul style={{ margin: 0, paddingLeft: 18, display: "grid", gap: 6 }}>
            {selectedKit.items.map((it) => (
              <li key={it}>{it}</li>
            ))}
          </ul>
        </div>
      </div>

      <div style={{ display: "flex", gap: 10 }}>
        <button onClick={create}>Create</button>
        <button onClick={onDone} style={{ opacity: 0.7 }}>
          Back
        </button>
      </div>

      {error && <div style={{ color: "crimson" }}>{error}</div>}
    </div>
  );
}
