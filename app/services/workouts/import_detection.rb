# frozen_string_literal: true

module Workouts
  # The generation of the file-derived facts reconciliation
  # (docs/dev/DERIVATIONS.md): how a stored original resolves its recording device,
  # its still-detected sport, and its virtual venue. Bump it when the platform
  # catalogue, the alias tables, or the facts rules change; the rebuild sweep
  # then re-reads only the workouts whose stored version is older, without
  # forcing a re-analysis.
  #
  # Version 3 replaced the hand-written FIT manufacturer table, nine of whose
  # codes named the wrong brand, by `Allure::Fit::Devices`, which also names
  # the model.
  module ImportDetection
    VERSION = 3

    # Every name the version-2 manufacturer table could store. A stored device
    # among them was derived from a code, not read from the file, so the
    # rebuild may replace it with the file's current name; any other stored
    # device is kept.
    SUPERSEDED_DEVICE_NAMES = [
      "Garmin", "Dynastream", "Suunto", "Wahoo Fitness", "North Pole Engineering",
      "Shimano", "iFit", "Stages Cycling", "Sigmasport", "TomTom", "Magellan", "Tacx",
      "Elite", "Polar", "Zwift", "Favero Electronics", "Strava", "Bryton", "SRAM",
      "TrainerRoad", "Omata", "Hammerhead", "COROS", "Whoop", "Decathlon", "Nike"
    ].freeze
  end
end
