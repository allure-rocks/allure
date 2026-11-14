import { defineConfig } from "vite";
import RubyPlugin from "vite-plugin-ruby";
import * as path from "node:path";

export default defineConfig({
  plugins: [RubyPlugin()],

  // The Scalar API reference (PLAN_API.md §13.2) ships Vue's esm-bundler
  // build, which expects these compile-time flags; without them it warns and
  // keeps the devtools hooks in the production bundle.
  define: {
    __VUE_OPTIONS_API__: "true",
    __VUE_PROD_DEVTOOLS__: "false",
    __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: "false",
  },

  resolve: {
    alias: {
      "~": path.resolve(import.meta.dirname, "app/frontend"),
    },
  },

  optimizeDeps: {
    // MapLibre 6 loads its web worker from a real URL relative to its own
    // module, rather than from a blob as version 5 did. Vite's dependency
    // pre-bundling rewrites maplibre-gl into .vite/deps/ without copying the
    // sibling maplibre-gl-worker.mjs next to it, so that URL 404s in
    // development. Nothing that needs tiling then renders — neither the vector
    // basemap nor our own GeoJSON track — while the background layer and DOM
    // markers still appear, which makes it look like a styling problem rather
    // than a broken worker.
    //
    // Excluding it leaves the package to be served from node_modules as-is, so
    // the worker resolves. The production build resolves it through Rolldown
    // and emits the worker as its own asset.
    exclude: ["maplibre-gl"],
  },

  css: {
    preprocessorOptions: {
      scss: {
        // Tabler's SCSS does `@import "bootstrap/scss/functions"`, i.e. a bare
        // node_modules specifier. Dart Sass needs node_modules on its load path
        // to resolve those.
        loadPaths: ["node_modules"],
        // Tabler 1.6 is still written against the legacy @import API. Silencing
        // the deprecation keeps the build output readable; revisit when Tabler
        // migrates to @use.
        silenceDeprecations: ["import", "global-builtin", "color-functions"],
        quietDeps: true,
      },
    },
  },

  server: {
    // Vite 8 rejects requests whose Host header it does not recognise. The Rails
    // container proxies to http://vite:3036, so the Host arriving here is the
    // compose service name — not localhost — and would otherwise be blocked.
    //
    // Extended via VITE_ALLOWED_HOSTS for the Tier-2 federation ring, where
    // instances address each other by network alias.
    allowedHosts: [
      "vite",
      "localhost",
      "allure.test",
      ...(process.env.VITE_ALLOWED_HOSTS?.split(",").map((h) => h.trim()).filter(Boolean) ?? []),
    ],
  },

  // No `server.hmr`/`server.ws` override here on purpose. vite-plugin-ruby
  // configures the dev server from VITE_RUBY_HOST/VITE_RUBY_PORT, and the
  // browser reaches it through ViteRuby's Rails proxy on :3000 — including the
  // HMR websocket upgrade. Setting it here only conflicts with the plugin.
});
