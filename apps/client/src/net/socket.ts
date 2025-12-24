const WS_URL = `ws://${location.hostname}:3030`;

export function connectSocket(onMessage: (data: any) => void) {
  const ws = new WebSocket(WS_URL);

  ws.onopen = () => console.log("WS connected:", WS_URL);
  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    onMessage(data);
  };
  ws.onerror = (e) => console.log("WS error", e);
  ws.onclose = () => console.log("WS closed");

  return ws;
}
