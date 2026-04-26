import { serve } from "@hono/node-server";
import app from "./index.js";

const port = Number(process.env.PORT) || 3003;
serve({ fetch: app.fetch, port }, () => {
  console.log(`🔥🥂 Roast or Toast running at http://localhost:${port}`);
});
