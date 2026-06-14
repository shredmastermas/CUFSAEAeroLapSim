import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// Standalone build: inlines ALL JavaScript, CSS and fonts into a single
// self-contained index.html that opens by double-clicking (file://) — no server,
// no install. The study data (sweep / trace / track / airfoils) is already inlined
// in the dashboard source, so the file is fully offline. Output: dist-single/.
// (The header logo and the About > downloads need the served build; everything
// else — every chart, the sweeps, the maps — works straight from the file.)
const here = dirname(fileURLToPath(import.meta.url));
const dep = (name) => resolve(here, "node_modules", name);

export default defineConfig({
  plugins: [react(), viteSingleFile()],
  resolve: {
    alias: {
      react: dep("react"),
      "react-dom": dep("react-dom"),
      xlsx: dep("xlsx"),
      papaparse: dep("papaparse"),
    },
  },
  build: {
    outDir: "dist-single",
    assetsInlineLimit: 100000000, // inline fonts as base64 too
    chunkSizeWarningLimit: 100000,
  },
});
