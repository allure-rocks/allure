# frozen_string_literal: true

# The small dataset: the two historical demo accounts with three activities
# each, two of them published. The federation ring seeds this one
# (docker-compose.fed.yml sets DEMO_DATASET=minimal) so the Tier-2 gate keeps
# its timing, and the full dataset falls back to it when the FIT corpus has
# not been fetched. Every entry keeps a committed GPX fixture as fallback.
require_relative "../emails"

module DemoSeed
  module Manifests
    # Re-dating anchors (docs/dev/DEMO.md). This dataset falls back on its
    # committed GPX fixtures when the corpus is missing, and those are the
    # newest recordings it can import, so the files anchor is the newest of
    # either source; spec/seeds/demo_manifest_spec.rb keeps it honest.
    MINIMAL_DATE_ANCHORS = { files: Date.new(2026, 9, 1), manual: Date.new(2026, 2, 16) }.freeze

    MINIMAL = {
      accounts: [
        {
          username: "marie",
          discoverable: "members",
          email: DemoSeed::Emails.for("marie"),
          display_name: "Marie Dufour",
          bio: "Trail et cyclisme dans les Alpes.",
          locale: "fr",
          built_in_profiles: { public: { settings: { "mask_start" => false, "mask_finish" => false, "gpx" => true } } },
          workouts: [
            { key: :trail, title: "Trail du matin", description: "Exemple importé depuis les fichiers de test FIT pour le développement local.",
              file: "Activity/2026/Activity_20260215_001_003_Running_Trail_Fenix7x_a790a6293770eda5fbd090ebfe8203b6.fit",
              fixture: "gpx/running_type.gpx", sport: "running", publish: :public },
            { key: :road, title: "Sortie route", description: "Exemple importé depuis les fichiers de test FIT pour le développement local.",
              file: "Activity/2026/Activity_20260217_002_007_Cycling_Road_Edge1050_7941c9691ae19ad740a6673e95ea837d.fit",
              fixture: "gpx/galibier.gpx", sport: "cycling_road", publish: :public },
            { key: :hike, title: "Randonnée", description: "Exemple importé depuis les fichiers de test FIT pour le développement local.",
              file: "Activity/2023/Activity_20230610_017_003_Hiking_Trail_Suunto-Vertical_d149673ba8d0667bef7a9fb68d91925d.fit" }
          ],
          # A workout typed in by hand (docs/dev/MANUAL-ENTRY.md).
          manual_workouts: [
            { key: :gym, sport: "strength_training", title: "Renforcement", started_at: "2026-02-16T18:30",
              duration: 2700, average_heart_rate: 115, calories: 290 }
          ]
        },
        {
          username: "paul",
          discoverable: "members",
          email: DemoSeed::Emails.for("paul"),
          display_name: "Paul Martin",
          bio: "Road cycling and morning loops.",
          locale: "en",
          built_in_profiles: { public: { settings: { "mask_start" => false, "mask_finish" => false, "gpx" => true } } },
          workouts: [
            { key: :mtb, title: "Mountain bike ride", description: "Sample imported from the FIT test files for local development.",
              file: "Activity/2026/Activity_20260114_002_008_Cycling_Mountain_EdgeMtb_da6a5e2deec8f950a983c0dd81ab28c0.fit",
              fixture: "gpx/multi_segment.gpx", sport: "mountain_biking", publish: :public },
            { key: :intervals, title: "Track intervals", description: "Sample imported from the FIT test files for local development.",
              file: "Activity/2013/Activity_20130102_001_000_Running_Fr610_4a74bacc229d62d7468d539f416b44e4.fit",
              fixture: "gpx/three_laps_recorded.gpx", sport: "running", publish: :public },
            { key: :virtual, title: "Virtual loop", description: "Sample imported from the FIT test files for local development.",
              file: "Activity/2022/Activity_20220120_001_058_Running_Virtual-Activity_Zwift_07fb1404b8cb257372bbdca01658d14d.fit",
              fixture: "gpx/route_repeat.gpx", sport: "running_virtual" }
          ]
        }
      ]
    }.freeze
  end
end
