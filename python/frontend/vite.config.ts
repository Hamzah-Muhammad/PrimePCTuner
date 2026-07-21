import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev-mode-only proxy: the built app is served by FastAPI from the same
// origin (app.py mounts frontend/dist), so /api is same-origin in
// production with zero CORS config needed — this proxy just gives `npm run
// dev` the same relative-path API calls to talk to during development.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": "http://127.0.0.1:8734",
    },
  },
});
