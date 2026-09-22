import { defineConfig } from "vite";

export default defineConfig({
  build: {
    outDir: "web/js-dist",
    chunkSizeWarningLimit: 2000,
    rollupOptions: {
      input: "./js/index.ts",
      preserveEntrySignatures: "exports-only",
      output: {
        entryFileNames: "index.js",
        format: "es",
        codeSplitting: false,
      },
    },
  },
});
