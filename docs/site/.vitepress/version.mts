import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

// The documented release is the application's own version, read from the
// file the release process bumps, so the site can never claim another one.
const versionFile = fileURLToPath(new URL("../../../config/version.rb", import.meta.url))
const match = readFileSync(versionFile, "utf8").match(/VERSION\s*=\s*"([^"]+)"/)

if (!match) throw new Error(`No VERSION found in ${versionFile}`)

export const version: string = match[1]
