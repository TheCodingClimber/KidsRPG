import { useEffect, useRef } from "react";

type ChatMsg = {
  id: string;
  from: "dm" | "player" | "system";
  text: string;
  ts: number;
};

export default function ChatPanel({
  title,
  messages,
}: {
  title: string;
  messages: ChatMsg[];
}) {
  const scrollerRef = useRef<HTMLDivElement | null>(null);
  const shouldAutoScrollRef = useRef(true);

  // Track whether the user is "near the bottom".
  function handleScroll() {
    const el = scrollerRef.current;
    if (!el) return;

    const distanceFromBottom = el.scrollHeight - (el.scrollTop + el.clientHeight);
    // If user is within 80px of bottom, we consider them "following" the log.
    shouldAutoScrollRef.current = distanceFromBottom < 80;
  }

  // Auto-scroll ONLY if user is already near bottom.
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
        borderRadius: 10,
        padding: 10,
        display: "grid",
        gridTemplateRows: "auto 1fr",
        gap: 10,
        boxSizing: "border-box",
      }}
    >
      <div style={{ fontWeight: 800 }}>{title}</div>

      <div
        ref={scrollerRef}
        onScroll={handleScroll}
        style={{
          overflow: "auto",
          padding: 10,
          border: "1px solid #444",
          borderRadius: 10,
          background: "rgba(0,0,0,0.03)",
          display: "grid",
          gap: 10,
        }}
      >
        {messages.map((m) => {
          const label = m.from === "dm" ? "DM" : m.from === "player" ? "You" : "System";

          // Make system text slightly larger + more vertical breathing room
          const isSystem = m.from === "system";

          return (
            <div key={m.id} style={{ lineHeight: isSystem ? 1.55 : 1.35 }}>
              <div style={{ fontWeight: 800, opacity: 0.8 }}>{label}</div>

              <div
                style={{
                  whiteSpace: "pre-wrap",
                  fontSize: isSystem ? 14.5 : 14,
                  padding: isSystem ? "6px 8px" : 0,
                  borderRadius: 8,
                  background: isSystem ? "rgba(0,0,0,0.06)" : "transparent",
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
