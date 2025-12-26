import { useState } from "react";

import PinLogin from "./screens/PinLogin";
import Menu from "./screens/Menu";
import CreateCharacter from "./screens/CreateCharacter";
import LoadGame from "./screens/LoadGame";
import Game from "./screens/Game";

type Screen = "menu" | "create" | "load" | "game";

export default function App() {
  const [authed, setAuthed] = useState(
    !!localStorage.getItem("sessionId")
  );
  const [screen, setScreen] = useState<Screen>("menu");
  const [activeCharId, setActiveCharId] = useState<string>("");

  function logout() {
    localStorage.removeItem("sessionId");
    localStorage.removeItem("accountId");
    location.reload();
  }

  // Not logged in → PIN screen
  if (!authed) {
    return <PinLogin onDone={() => setAuthed(true)} />;
  }

  // Menu
  if (screen === "menu") {
    return (
      <Menu
        onSelect={(s) => {
          if (s === "new" || s === "create") setScreen("create");
          if (s === "load") setScreen("load");
        }}
        onLogout={logout}
      />
    );
  }

  // Create Character
  if (screen === "create") {
    return (
      <CreateCharacter
        onDone={() => {
          setScreen("load");
        }}
      />
    );
  }

  // Load Game
  if (screen === "load") {
    return (
      <LoadGame
        onLoad={(characterId) => {
          setActiveCharId(characterId);
          setScreen("game");
        }}
      />
    );
  }

  // Game
  return (
  <Game
    characterId={activeCharId}
    onExitToMenu={() => setScreen("menu")}
  />
);

}
