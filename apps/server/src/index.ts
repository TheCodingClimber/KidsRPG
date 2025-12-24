import http from "node:http";
import { createHttpServer } from "./http.js";
import { createWsServer } from "./ws.js";
import { PORT } from "./config.js";

const app = createHttpServer();
const server = http.createServer(app);

createWsServer(server);

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
