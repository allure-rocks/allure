import { defineConfig } from "vitepress"
import { version } from "./version.mts"
import versions from "../versions.json"

// The only host-specific values. Moving the repository (to GitHub, say) means
// changing these two lines and the CI job; see docs/site/README.md.
const REPOSITORY_URL = "https://github.com/allure-rocks/allure"
const EDIT_LINK_PATTERN = `${REPOSITORY_URL}/edit/main/docs/site/:path`

type ArchivedVersion = { version: string; path: string }
const archived: ArchivedVersion[] = versions.archived

export default defineConfig({
  title: "Allure",
  titleTemplate: ":title · Allure documentation",
  description: "Install, configure and operate an Allure instance.",
  lang: "en-GB",
  // A release older than the latest is built under its own sub-path
  // (DOCS_BASE=/v0.8/) and listed in versions.json.
  base: process.env.DOCS_BASE || "/",
  cleanUrls: true,
  lastUpdated: false,
  srcExclude: ["README.md"],
  head: [["link", { rel: "icon", type: "image/svg+xml", href: "/icon.svg" }]],

  themeConfig: {
    logo: "/icon.svg",
    search: { provider: "local" },
    outline: { level: [2, 3] },

    nav: [
      { text: "Guide", link: "/guide/what-is-allure", activeMatch: "^/guide/" },
      { text: "Installation", link: "/install/quick-start", activeMatch: "^/install/" },
      { text: "Configuration", link: "/configuration/environment", activeMatch: "^/configuration/" },
      { text: "Features", link: "/features/federation", activeMatch: "^/features/" },
      { text: "Operations", link: "/operations/upgrading", activeMatch: "^/(operations|reference)/" },
      {
        text: `v${version}`,
        items: [
          { text: `v${version} (latest)`, link: "/" },
          ...archived.map(({ version, path }) => ({ text: `v${version}`, link: path })),
          { text: "Changelog", link: `${REPOSITORY_URL}/-/blob/main/CHANGELOG.md` }
        ]
      }
    ],

    sidebar: [
      {
        text: "Guide",
        items: [
          { text: "What is Allure?", link: "/guide/what-is-allure" },
          { text: "Requirements", link: "/guide/requirements" },
          { text: "How an instance works", link: "/guide/architecture" }
        ]
      },
      {
        text: "Installation",
        items: [
          { text: "Quick start", link: "/install/quick-start" },
          { text: "Secrets and keys", link: "/install/secrets" },
          { text: "Reverse proxy and TLS", link: "/install/reverse-proxy" },
          { text: "First account", link: "/install/first-account" },
          { text: "Compose overrides", link: "/install/overrides" }
        ]
      },
      {
        text: "Configuration",
        items: [
          { text: "Environment reference", link: "/configuration/environment" },
          { text: "Instance identity", link: "/configuration/instance" },
          { text: "Registration and invitations", link: "/configuration/registration" },
          { text: "Mail", link: "/configuration/mail" },
          { text: "Maps and route images", link: "/configuration/maps" }
        ]
      },
      {
        text: "Optional features",
        items: [
          { text: "Federation", link: "/features/federation" },
          { text: "Identity providers", link: "/features/identity-providers" },
          { text: "Geocoding", link: "/features/geocoding" },
          { text: "Terrain elevation", link: "/features/elevation" },
          { text: "Weather", link: "/features/weather" },
          { text: "Workout assistant", link: "/features/assistant" },
          { text: "Photos", link: "/features/photos" },
          { text: "Instance funding", link: "/features/funding" },
          { text: "Remote imports", link: "/features/remote-imports" },
          { text: "Push notifications", link: "/features/push" },
          { text: "API, webhooks and MCP", link: "/features/api" }
        ]
      },
      {
        text: "Operations",
        items: [
          { text: "Upgrading", link: "/operations/upgrading" },
          { text: "Backups and restore", link: "/operations/backups" },
          { text: "Background jobs", link: "/operations/jobs" },
          { text: "Administration console", link: "/operations/admin" },
          { text: "Accounts", link: "/operations/accounts" },
          { text: "Monitoring", link: "/operations/monitoring" },
          { text: "Troubleshooting", link: "/operations/troubleshooting" }
        ]
      },
      {
        text: "Reference",
        items: [{ text: "CLI tasks", link: "/reference/cli" }]
      }
    ],

    editLink: { pattern: EDIT_LINK_PATTERN, text: "Edit this page" },
    socialLinks: [{ icon: "github", link: REPOSITORY_URL }],

    footer: {
      message: "Released under the GNU Affero General Public License v3.0 or later.",
      copyright: "Allure contributors"
    }
  }
})
