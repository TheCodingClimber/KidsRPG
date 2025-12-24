import { useState } from "react";
import { postJson } from "../net/api";

type AuthResponse = { accountId: string; sessionId: string; expiresAt: number };

export default function PinLogin({ onDone }: { onDone: () => void }) {
  const [name, setName] = useState("");
  const [pin, setPin] = useState("");
  const [mode, setMode] = useState<"login" | "register">("login");
  const [error, setError] = useState("");

  async function submit() {
    setError("");
    try {
      const path = mode === "register" ? "/auth/register" : "/auth/login";
      const data = await postJson<AuthResponse>(path, { name, pin });
      localStorage.setItem("sessionId", data.sessionId);
      localStorage.setItem("accountId", data.accountId);
      onDone();
    } catch (e: any) {
      setError(e.message || "Failed");
    }
  }

  return (
    <div style={{ padding: 24, display: "grid", gap: 10, maxWidth: 360 }}>
      <h3>{mode === "login" ? "Enter PIN" : "Create Account"}</h3>

      <input placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} />
      <input
        placeholder="PIN (4+ digits)"
        value={pin}
        onChange={(e) => setPin(e.target.value)}
        inputMode="numeric"
        type="password"
      />

      <button onClick={submit}>{mode === "login" ? "Login" : "Register"}</button>

      <button
        onClick={() => setMode(mode === "login" ? "register" : "login")}
        style={{ opacity: 0.8 }}
      >
        {mode === "login" ? "New player? Register" : "Already have an account? Login"}
      </button>

      {error && <div style={{ color: "crimson" }}>{error}</div>}
    </div>
  );
}
