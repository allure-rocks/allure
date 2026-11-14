# frozen_string_literal: true

# Development demo dataset, loaded by db/seeds.rb in development only.
#
# DEMO_DATASET picks the manifest: `full` (default) is the ten-persona dataset
# built from the optional FIT conformance corpus (script/fetch-fit-corpus);
# `minimal` is the two-account set the federation ring uses. Without the
# corpus, `full` falls back to `minimal`, whose entries carry committed GPX
# fixtures. DEMO_SEED_LIMIT=n imports at most n activities per account, for a
# quick run while working on the seed itself.
#
# The dataset is re-dated near the present like the demo instance's
# (PLAN_DEMO.md §2): it ends yesterday on a fresh database, and a database that
# already holds it keeps the dates of its first run. DEMO_SEED_SHIFT=0 keeps the
# files' own dates instead.
require_relative "demo/seeder"
require_relative "demo/datasets"

corpus_root = Rails.root.join("references_apps/fit-test-files")
dataset = ENV.fetch("DEMO_DATASET", "full").strip.downcase
if dataset == "full" && !corpus_root.join("Activity").directory?
  puts "[seeds] the FIT corpus is missing: run script/fetch-fit-corpus for the full dataset; seeding the minimal one"
  dataset = "minimal"
end

begin
  selected = DemoSeed::Datasets.fetch(dataset)
rescue ArgumentError => error
  abort("[seeds] #{error.message}")
end
manifest = selected.manifest
dating = if ENV["DEMO_SEED_SHIFT"].to_s.strip == "0"
  DemoSeed::Dating.none
else
  DemoSeed::Dating.near_present(anchors: selected.anchors, usernames: manifest.fetch(:accounts).map { |account| account.fetch(:username) })
end

limit = ENV["DEMO_SEED_LIMIT"].presence&.then { |value| Integer(value, 10) }
summary = DemoSeed::Runner.new(
  manifest:,
  corpus_root:,
  fixtures_root: Rails.root.join("spec/fixtures"),
  limit:,
  file_time_shift: dating.file_shift,
  manual_time_shift: dating.manual_shift
).call

puts "[seeds] demo ready (#{dataset}) — every account signs in with #{DemoSeed::PASSWORD}, " \
     "second factor: TOTP secret #{DemoSeed::TOTP_SECRET}"
puts "[seeds] accounts: #{manifest.fetch(:accounts).map { |account| account.fetch(:username) }.join(', ')}"
puts "[seeds] API token (tom, REST and MCP): #{DemoSeed::API_TOKEN_SECRET}" if dataset == "full"
puts "[seeds] publications, route images, matching and geocoding finish on the workers: keep `dip up` running"
puts "[seeds] #{summary.failed} step(s) failed; see the lines above" if summary.failed.positive?
