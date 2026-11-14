# frozen_string_literal: true

module Allure
  module Withings
    # Maps Withings's workout categories (the enum the public API documents
    # and the private listing carries) onto Allure's vocabulary
    # (PLAN_REMOTE_IMPORTS.md §7c.3). Two views over one table:
    #
    # - `sport_name` is the TCX `<Activity Sport>` value, among the names
    #   Allure's TCX parser resolves (`Allure::Tcx::Parser::SPORT_ALIASES`);
    #   unknown categories become "Other", which emits no signal so the
    #   fallback sport answers;
    # - `slug` is the catalog sport slice 5 passes as `declared_sport`,
    #   outranking the file's detection. `nil` means Allure's catalog has no
    #   equivalent, and the connection's fallback sport answers too.
    #
    # Indoor categories map to their outdoor sport: positionlessness is a
    # recording property, not a sport.
    module SportMapping
      CATEGORIES = {
        1 => "walking",          # Walk
        2 => "running",          # Run
        3 => "hiking",           # Hiking
        4 => "inline_skating",   # Skating (roller); 196 is the ice one
        5 => "cycling",          # BMX
        6 => "cycling",          # Bicycling
        7 => "pool_swimming",    # Swimming (the watches count pool laps)
        10 => "windsurfing",     # Windsurfing
        12 => "tennis_outdoor",  # Tennis
        16 => "strength_training", # Lift weights
        17 => "fitness",         # Calisthenics
        18 => "fitness",        # Elliptical
        19 => "fitness",        # Pilates
        28 => "fitness",        # Yoga
        29 => "fitness",        # Dancing
        30 => "fitness",        # Boxing
        33 => "fitness",        # Martial arts
        35 => "snowboarding",   # Snowboarding
        187 => "rowing",        # Rowing
        188 => "fitness",       # Zumba
        196 => "ice_skating",   # Ice skating
        307 => "running",       # Indoor running
        308 => "cycling"        # Indoor cycling
      }.freeze

      # Only the categories whose sport the TCX parser resolves; everything
      # else is "Other" and lets the fallback sport answer.
      TCX_SPORT_NAMES = {
        1 => "Walking",
        2 => "Running",
        3 => "Hiking",
        6 => "Biking",
        7 => "Swimming"
      }.freeze
      OTHER_SPORT_NAME = "Other"

      module_function

      # The catalog slug, or nil when Allure has no equivalent sport.
      def slug(category) = CATEGORIES[category.to_i]

      # The TCX `<Activity Sport>` value for the same category.
      def sport_name(category) = TCX_SPORT_NAMES[category.to_i] || OTHER_SPORT_NAME

      # The Withings name for a category, for logs and the probe report.
      NAMES = {
        1 => "Walk", 2 => "Run", 3 => "Hiking", 4 => "Skating", 5 => "BMX",
        6 => "Bicycling", 7 => "Swimming", 8 => "Surfing", 9 => "Kitesurfing",
        10 => "Windsurfing", 11 => "Bodyboard", 12 => "Tennis",
        13 => "Table tennis", 14 => "Squash", 15 => "Badminton",
        16 => "Lift weights", 17 => "Calisthenics", 18 => "Elliptical",
        19 => "Pilates", 20 => "Basketball", 21 => "Soccer", 22 => "Football",
        23 => "Rugby", 24 => "Volleyball", 25 => "Waterpolo", 26 => "Horse riding",
        27 => "Golf", 28 => "Yoga", 29 => "Dancing", 30 => "Boxing",
        31 => "Fencing", 32 => "Wrestling", 33 => "Martial arts", 34 => "Skiing",
        35 => "Snowboarding", 36 => "Other", 128 => "No activity",
        187 => "Rowing", 188 => "Zumba", 191 => "Baseball", 192 => "Handball",
        193 => "Hockey", 194 => "Ice hockey", 195 => "Climbing",
        196 => "Ice skating", 272 => "Multi sport", 307 => "Indoor running",
        308 => "Indoor cycling"
      }.freeze

      def name(category) = NAMES[category.to_i] || "category #{category}"
    end
  end
end
