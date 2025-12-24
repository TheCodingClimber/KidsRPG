import { WebSocketServer } from "ws";
import type { Server } from "node:http";

export function createWsServer(server: Server) {
  const wss = new WebSocketServer({ server });

  wss.on("connection", (ws) => {
    console.log("WS client connected");
    ws.send(JSON.stringify({ type: "hello", message: "Welcome to Norse RPG" }));
  });
}
