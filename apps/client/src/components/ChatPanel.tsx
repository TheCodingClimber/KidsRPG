import { useEffect, useRef } from "react";

export type ChatMsg = {
  id: string;
  from: "dm" | "player" | "system" | "npc";
  text: string;
  ts: number;
};

export default function ChatPanel({
  title = "Adventure Log",
  showTitle = true,
  messages,
}: {
  title?: string;
  showTitle?: boolean;
  messages: ChatMsg[];
}) {
  const scrollerRef = useRef<HTMLDivElement | null>(null);
  const shouldAutoScrollRef = useRef(true);

  function handleScroll() {
    const el = scrollerRef.current;
    if (!el) return;
    const distanceFromBottom = el.scrollHeight - (el.scrollTop + el.clientHeight);
    shouldAutoScrollRef.current = distanceFromBottom < 80;
  }

  useEffect(() => {
    const el = scrollerRef.current;
    if (!el) return;
    if (!shouldAutoScrollRef.current) return;
    el.scrollTop = el.scrollHeight;
  }, [messages.length]);

  return (
    <div
      style={{
        height: "100%",
        border: "1px solid #333",
        borderRadius: 12,
        padding: 12,
        display: "grid",
        gridTemplateRows: showTitle ? "auto 1fr" : "1fr",
        gap: 10,
        boxSizing: "border-box",
        minHeight: 0,
        background: "rgba(10, 10, 10, 0.35)",
      }}
    >
      {showTitle && (
        <div style={{ fontWeight: 900, letterSpacing: 0.3, opacity: 0.95 }}>
          {title}
        </div>
      )}

      <div
        ref={scrollerRef}
        onScroll={handleScroll}
        style={{
          overflow: "auto",
          padding: 12,
          border: "1px solid #2b2b2b",
          borderRadius: 12,
          background: "rgba(0,0,0,0.25)",
          display: "grid",
          gap: 12,
          minHeight: 0,
        }}
      >
        {messages.map((m) => {
          const label =
            m.from === "dm"
              ? "DM"
              : m.from === "player"
              ? "You"
              : m.from === "npc"
              ? "NPC"
              : "System";

          const isSystem = m.from === "system";

          return (
            <div key={m.id} style={{ lineHeight: isSystem ? 1.6 : 1.35 }}>
              {/* ✅ Hide the inner "System" label to prevent the double-System look */}
              {!isSystem && (
                <div style={{ fontWeight: 800, opacity: 0.8 }}>
                  {label}
                </div>
              )}

              <div
                style={{
                  whiteSpace: "pre-wrap",
                  fontSize: 14.5,
                  padding: isSystem ? "8px 10px" : "6px 8px",
                  borderRadius: 10,
                  background: isSystem
                    ? "rgba(255,255,255,0.04)"
                    : "rgba(255,255,255,0.02)",
                  border: "1px solid rgba(255,255,255,0.04)",
                }}
              >
                {m.text}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
