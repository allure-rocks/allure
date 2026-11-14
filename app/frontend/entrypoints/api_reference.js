// The Scalar API reference document (PLAN_API.md §13.2), loaded inside the
// /developers/api page's iframe. It is a document of its own, without Tabler:
// Tabler's utility classes (.grid, .p-3, .rounded…) share names with Scalar's
// and would otherwise rewrite its layout.
//
// Everything that would reach a Scalar service is off — proxy, web fonts,
// telemetry, the AI agent, developer tools — and a pasted token stays in
// memory only. "Test Request" goes to this page's own origin. The embedding
// page posts the light/dark theme whenever it changes.
import "@scalar/api-reference/style.css";
import "~/styles/api_reference.css";
import { createApiReference } from "@scalar/api-reference";

const mount = document.getElementById("api-reference");
const root = document.documentElement;

const themeState = () => (root.dataset.theme === "dark" ? "dark" : "light");

let configuration = {
  url: mount.dataset.url,
  servers: [{ url: new URL(mount.dataset.basePath, window.location.origin).href }],
  theme: "default",
  layout: "modern",
  forceDarkModeState: themeState(),
  hideDarkModeToggle: true,
  withDefaultFonts: false,
  telemetry: false,
  persistAuth: false,
  showDeveloperTools: "never",
  agent: { disabled: true },
  documentDownloadType: "none",
  hideClientButton: true,
  showOperationId: true,
  showExtensions: ["x-allure-scope"],
  orderSchemaPropertiesBy: "preserve",
  authentication: { preferredSecurityScheme: "bearerAuth" },
  localization: { locale: mount.dataset.locale },
};

const reference = createApiReference(mount, configuration);

window.addEventListener("message", (event) => {
  if (event.origin !== window.location.origin || event.data?.type !== "allure:theme") return;

  root.dataset.theme = event.data.theme === "dark" ? "dark" : "light";
  configuration = { ...configuration, forceDarkModeState: themeState() };
  reference.updateConfiguration(configuration);
  // Scalar reads forceDarkModeState only at mount; its mode lives in these
  // two body classes.
  document.body.classList.toggle("dark-mode", themeState() === "dark");
  document.body.classList.toggle("light-mode", themeState() === "light");
});
