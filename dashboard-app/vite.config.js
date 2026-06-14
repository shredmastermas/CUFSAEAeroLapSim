import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const here = dirname(fileURLToPath(import.meta.url));
const dep = (name) => resolve(here, "node_modules", name);

export default defineConfig({
  plugins: [react()],
  resolve: {
    // the dashboard jsx lives in ../handover/dashboard (outside this app
    // root), so its bare imports must be pinned to this app's node_modules
    alias: {
      react: dep("react"),
      "react-dom": dep("react-dom"),
      xlsx: dep("xlsx"),
      papaparse: dep("papaparse"),
    },
  },
  server: {
    fs: { allow: [".."] },
    port: 5273,
    host: "0.0.0.0", // bind all interfaces so the dev server is reachable remotely
    allowedHosts: true, // permit any host header, not just IPs
  },
  preview: {
    // the prebuilt dist/ served for remote viewing. content-hashed assets
    // still cache + 304 via etag; "no-cache" forces index.html to revalidate
    // every load so a rebuild shows up without a manual hard-refresh.
    port: 5280,
    strictPort: true,
    host: "0.0.0.0",
    allowedHosts: true,
    headers: { "Cache-Control": "no-cache" },
  },
});
