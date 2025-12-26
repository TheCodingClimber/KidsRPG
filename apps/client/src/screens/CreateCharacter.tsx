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

/** =========================
 * New: Home Towns (1 city, 3 towns, 5 villages)
 * ========================= */
const HOME_TOWNS = [
  // 1 city
  { id: "cinderport_city", name: "Cinderport (City)", type: "city", vibe: "Big markets, big rumors, big trouble." },

  // 3 towns
  { id: "brindlewick_town", name: "Brindlewick (Town)", type: "town", vibe: "Warm hearths, honest folk, and secret paths." },
  { id: "stoneford_town", name: "Stoneford (Town)", type: "town", vibe: "Sturdy bridges, stubborn guards, and river trade." },
  { id: "pinehollow_town", name: "Pinehollow (Town)", type: "town", vibe: "Forest-edge hunters and whispers in the trees." },

  // 5 villages
  { id: "willowmere_village", name: "Willowmere (Village)", type: "village", vibe: "Soft marsh lights and old stories." },
  { id: "goldenfield_village", name: "Goldenfield (Village)", type: "village", vibe: "Bright farms, friendly faces, hidden barns." },
  { id: "ravenwatch_village", name: "Ravenwatch (Village)", type: "village", vibe: "Cliff huts and watchfires at night." },
  { id: "mistvale_village", name: "Mistvale (Village)", type: "village", vibe: "Foggy mornings and weird footprints." },
  { id: "emberbrook_village", name: "Emberbrook (Village)", type: "village", vibe: "A creek, a mill, and a brave little militia." },
] as const;

/** =========================
 * New: Banner + Sigil + Avatar
 * ========================= */
const BANNER_COLORS = [
  { id: "crimson", name: "Crimson" },
  { id: "royal_blue", name: "Royal Blue" },
  { id: "emerald", name: "Emerald" },
  { id: "midnight", name: "Midnight Black" },
  { id: "gold", name: "Golden" },
  { id: "purple", name: "Violet" },
  { id: "ice", name: "Ice White" },
  { id: "copper", name: "Copper" },
  { id: "teal", name: "Teal" },
  { id: "scarlet", name: "Scarlet" },
] as const;

const SIGILS = [
  { id: "sword", name: "Sword" },
  { id: "shield", name: "Shield" },
  { id: "crown", name: "Crown" },
  { id: "dragon", name: "Dragon" },
  { id: "wolf", name: "Wolf" },
  { id: "oak", name: "Oak Tree" },
  { id: "star", name: "Star" },
  { id: "moon", name: "Moon" },
  { id: "hammer", name: "Hammer" },
  { id: "compass", name: "Compass" },
] as const;

const AVATARS = [
  { id: "knight", emoji: "🛡️", name: "Knight" },
  { id: "sword", emoji: "🗡️", name: "Swordsman" },
  { id: "archer", emoji: "🏹", name: "Archer" },
  { id: "mage", emoji: "🧙‍♂️", name: "Mage" },
  { id: "elf", emoji: "🧝‍♂️", name: "Elf" },
  { id: "dwarf", emoji: "⛏️", name: "Dwarf" },
  { id: "rogue", emoji: "🗝️", name: "Rogue" },
  { id: "healer", emoji: "✨", name: "Healer" },
  { id: "dragon", emoji: "🐉", name: "Dragonfriend" },
  { id: "crown", emoji: "👑", name: "Royal" },
] as const;

/** =========================
 * New: Promise (10 choices)
 * ========================= */
const PROMISES = [
  { id: "promise_protect_family", name: "Protect my family no matter what" },
  { id: "promise_become_champion", name: "Become the Champion of the realm" },
  { id: "promise_find_lost_relic", name: "Find a lost relic from ancient ruins" },
  { id: "promise_slayers_oath", name: "Defeat the bandit camps threatening travelers" },
  { id: "promise_map_everywhere", name: "Map every town, village, and secret road" },
  { id: "promise_save_city", name: "Help the great city when it calls for heroes" },
  { id: "promise_master_magic", name: "Learn powerful magic the right way" },
  { id: "promise_dragon_rider", name: "Reach the mountain summit and tame a dragon" },
  { id: "promise_restore_ruins", name: "Restore a ruined place into something good" },
  { id: "promise_make_allies", name: "Make allies in every settlement" },
] as const;

/** =========================
 * Updated: Lucky Charms (10 choices) + perks
 * ========================= */
const CHARMS = [
  {
    id: "charm_lucky_coin",
    name: "Lucky Coin",
    perk: "Once per in-game day, a bad outcome may be softened (fail → partial success).",
    flavor: "A coin that feels warm when trouble is near.",
  },
  {
    id: "charm_feather",
    name: "Swift Feather",
    perk: "Slightly better chance to act first and slip away from danger.",
    flavor: "Light as air. Quick as a thought.",
  },
  {
    id: "charm_old_key",
    name: "Old Key (mystery)",
    perk: "More chances to discover hidden doors, shortcuts, or locked secrets.",
    flavor: "It doesn’t fit… until it does.",
  },
  {
    id: "charm_rune_stone",
    name: "Rune Stone",
    perk: "More consistent luck: fewer streaks of bad rolls.",
    flavor: "Steady hands. Clear mind.",
  },
  {
    id: "charm_glass_marble",
    name: "Glass Marble",
    perk: "Occasionally gives a small warning before danger or a risky choice.",
    flavor: "Sometimes it clouds… then clears.",
  },
  {
    id: "charm_silver_bell",
    name: "Silver Bell",
    perk: "Slightly fewer ambushes while traveling; safer returns.",
    flavor: "A tiny ring that keeps shadows away.",
  },
  {
    id: "charm_ember_charm",
    name: "Ember Charm",
    perk: "Bravery boost: slightly better vs fear and intimidation.",
    flavor: "A warm spark against your chest.",
  },
  {
    id: "charm_sea_shell",
    name: "Sea Shell",
    perk: "Peaceful path boost: better odds at calming NPCs and avoiding fights.",
    flavor: "Your voice becomes calm like waves.",
  },
  {
    id: "charm_starlit_pin",
    name: "Starlit Pin",
    perk: "Very rare ‘destiny moments’: lucky timing, rare allies, or special finds.",
    flavor: "When it glints, fate is watching.",
  },
  {
    id: "charm_iron_token",
    name: "Iron Token",
    perk: "Endurance boost: slightly better on long journeys and survival moments.",
    flavor: "Heavy, steady, unbreakable.",
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

  // NEW
  const [homeTownId, setHomeTownId] =
    useState<(typeof HOME_TOWNS)[number]["id"]>("brindlewick_town");

  const [bannerColor, setBannerColor] =
    useState<(typeof BANNER_COLORS)[number]["id"]>("crimson");

  const [sigilId, setSigilId] =
    useState<(typeof SIGILS)[number]["id"]>("sword");

  const [avatarEmoji, setAvatarEmoji] =
    useState<(typeof AVATARS)[number]["emoji"]>("🛡️");

  const [promiseId, setPromiseId] =
    useState<(typeof PROMISES)[number]["id"]>("promise_dragon_rider");

  const [charmId, setCharmId] =
    useState<(typeof CHARMS)[number]["id"]>("charm_lucky_coin");

  const [error, setError] = useState("");

  const selectedPersonality = useMemo(
    () => PERSONALITIES.find((p) => p.id === personalityId)!,
    [personalityId]
  );

  const selectedKit = useMemo(
    () => STARTER_KITS.find((k) => k.id === kitId)!,
    [kitId]
  );

  const selectedHomeTown = useMemo(
    () => HOME_TOWNS.find((h) => h.id === homeTownId)!,
    [homeTownId]
  );

  const selectedAvatar = useMemo(
    () => AVATARS.find((a) => a.emoji === avatarEmoji)!,
    [avatarEmoji]
  );

  const selectedPromise = useMemo(
    () => PROMISES.find((p) => p.id === promiseId)!,
    [promiseId]
  );

  const selectedCharm = useMemo(
    () => CHARMS.find((c) => c.id === charmId)!,
    [charmId]
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
        starterKitId: selectedKit.id,

        // NEW
        homeTownId,
        bannerColor,
        sigilId,
        avatarEmoji,
        promiseId,
        charmId,
      });

      onDone();
    } catch (e: any) {
      setError(e.message || "Failed");
    }
  }

  return (
    <div style={{ padding: 24, display: "grid", gap: 12, maxWidth: 920 }}>
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

      {/* Home Town */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 12,
          alignItems: "start",
        }}
      >
        <label style={{ display: "grid", gap: 6 }}>
          Home Town
          <select
            value={homeTownId}
            onChange={(e) =>
              setHomeTownId(e.target.value as (typeof HOME_TOWNS)[number]["id"])
            }
          >
            {HOME_TOWNS.map((h) => (
              <option key={h.id} value={h.id}>
                {h.name}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            Your home town can affect future rumors, discounts, and story hooks.
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
            {selectedHomeTown.name}
          </div>
          <div style={{ opacity: 0.8 }}>{selectedHomeTown.vibe}</div>
        </div>
      </div>

      {/* Banner / Sigil / Avatar */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 12,
          alignItems: "start",
        }}
      >
        <label style={{ display: "grid", gap: 6 }}>
          Banner Color
          <select
            value={bannerColor}
            onChange={(e) =>
              setBannerColor(e.target.value as (typeof BANNER_COLORS)[number]["id"])
            }
          >
            {BANNER_COLORS.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            Your banner can show up in the UI later (map pin, save slot, party list).
          </div>
        </label>

        <label style={{ display: "grid", gap: 6 }}>
          Sigil
          <select
            value={sigilId}
            onChange={(e) =>
              setSigilId(e.target.value as (typeof SIGILS)[number]["id"])
            }
          >
            {SIGILS.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            Your sigil is your symbol—perfect for a hero’s identity.
          </div>
        </label>

        <label style={{ display: "grid", gap: 6 }}>
          Avatar
          <select
            value={avatarEmoji}
            onChange={(e) =>
              setAvatarEmoji(e.target.value as (typeof AVATARS)[number]["emoji"])
            }
          >
            {AVATARS.map((a) => (
              <option key={a.id} value={a.emoji}>
                {a.emoji} {a.name}
              </option>
            ))}
          </select>
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
            Preview
          </div>
          <div style={{ display: "flex", gap: 10, alignItems: "center", fontSize: 22 }}>
            <span title="Avatar">{selectedAvatar.emoji}</span>
            <span style={{ fontSize: 14, opacity: 0.8 }}>
              Banner: <b>{BANNER_COLORS.find((c) => c.id === bannerColor)!.name}</b> • Sigil:{" "}
              <b>{SIGILS.find((s) => s.id === sigilId)!.name}</b>
            </span>
          </div>
        </div>
      </div>

      {/* Promise + Charm */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 12,
          alignItems: "start",
        }}
      >
        <label style={{ display: "grid", gap: 6 }}>
          Promise (Oath)
          <select
            value={promiseId}
            onChange={(e) =>
              setPromiseId(e.target.value as (typeof PROMISES)[number]["id"])
            }
          >
            {PROMISES.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            Your promise helps guide your story. It can unlock special quests later.
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
          <div style={{ fontWeight: 800, marginBottom: 6 }}>Chosen Promise</div>
          <div style={{ opacity: 0.85 }}>{selectedPromise.name}</div>
        </div>

        <label style={{ display: "grid", gap: 6 }}>
          Lucky Charm
          <select
            value={charmId}
            onChange={(e) =>
              setCharmId(e.target.value as (typeof CHARMS)[number]["id"])
            }
          >
            {CHARMS.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>

          <div style={{ opacity: 0.75, fontSize: 12 }}>
            A tiny “luck flavor” that can affect future rolls/events later.
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
          <div style={{ fontWeight: 800, marginBottom: 6 }}>Chosen Charm</div>
          <div style={{ opacity: 0.92, fontWeight: 700 }}>{selectedCharm.name}</div>
          <div style={{ opacity: 0.85, marginTop: 6 }}>{selectedCharm.perk}</div>
          {selectedCharm.flavor ? (
            <div style={{ opacity: 0.7, marginTop: 8, fontStyle: "italic" }}>
              “{selectedCharm.flavor}”
            </div>
          ) : null}
        </div>
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
