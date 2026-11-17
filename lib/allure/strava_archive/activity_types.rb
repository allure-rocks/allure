# frozen_string_literal: true

module Allure
  module StravaArchive
    # Maps the activity type of an `activities.csv` row to a catalog sport
    # (docs/dev/STRAVA-ARCHIVE.md). The archive writes the type in the athlete's
    # display language: the API names, the English labels and the French and
    # German ones are listed here; any other label must equal an alias of
    # `Allure::ActivityTypeCatalog` exactly. Nothing is matched by substring, so
    # an unknown label resolves to nothing rather than to a wrong sport.
    module ActivityTypes
      TYPES = {
        "cycling" => [
          "Ride", "Handcycle", "Velomobile", "Vélo", "Sortie à vélo", "Handbike",
          "Vélo couché", "Radfahrt", "Liegerad"
        ],
        "cycling_gravel" => [ "GravelRide", "Gravel Ride", "Sortie gravel", "Vélo gravel", "Gravel-Fahrt", "Gravelfahrt" ],
        "cycling_electric" => [ "EBikeRide", "E-Bike Ride", "Vélo électrique", "Sortie en vélo électrique", "E-Bike-Fahrt" ],
        "mountain_biking" => [
          "MountainBikeRide", "Mountain Bike Ride", "VTT", "Sortie VTT", "Mountainbike-Fahrt", "Mountainbikefahrt"
        ],
        "mountain_biking_electric" => [
          "EMountainBikeRide", "E-Mountain Bike Ride", "VTT électrique", "Sortie en VTT électrique",
          "E-Mountainbike-Fahrt"
        ],
        "cycling_virtual" => [ "VirtualRide", "Virtual Ride", "Vélo virtuel", "Sortie virtuelle", "Virtuelle Radfahrt" ],
        "running" => [ "Run", "Course à pied", "Course", "Lauf" ],
        "trail" => [ "TrailRun", "Trail Run", "Trail", "Trailrun", "Traillauf" ],
        "running_virtual" => [ "VirtualRun", "Virtual Run", "Course virtuelle", "Virtueller Lauf" ],
        "walking" => [ "Walk", "Marche", "Spaziergang", "Gehen" ],
        "hiking" => [ "Hike", "Randonnée", "Randonnée pédestre", "Wanderung", "Wandern" ],
        "snowshoes" => [ "Snowshoe", "Raquettes", "Raquette à neige", "Schneeschuhwandern", "Schneeschuhlaufen" ],
        "skiing_alpine" => [ "AlpineSki", "Alpine Ski", "Ski alpin", "Ski Alpin" ],
        "skiing_touring" => [
          "BackcountrySki", "Backcountry Ski", "Ski de randonnée", "Ski de rando", "Skitour", "Skitouren"
        ],
        "skiing_cross_country" => [
          "NordicSki", "Nordic Ski", "Ski nordique", "Ski de fond", "Langlauf", "Skilanglauf"
        ],
        "snowboarding" => [ "Snowboard" ],
        "ice_skating" => [ "IceSkate", "Ice Skate", "Patinage", "Patin à glace", "Patinage sur glace", "Eislaufen" ],
        "inline_skating" => [ "InlineSkate", "Inline Skate", "Roller", "Patin à roues alignées", "Inlineskaten" ],
        "open_water_swimming" => [ "Swim", "Natation", "Schwimmen" ],
        "rowing" => [ "Rowing", "Aviron", "Rudern" ],
        "rowing_virtual" => [ "VirtualRow", "Virtual Row", "Aviron virtuel", "Virtuelles Rudern" ],
        "kayaking" => [ "Kayaking", "Kayak", "Kajakfahren", "Kajak" ],
        "canoeing" => [ "Canoeing", "Canoë", "Canoë-kayak", "Kanufahren", "Kanu" ],
        "standup_paddleboarding" => [
          "StandUpPaddling", "Stand Up Paddling", "Stand up paddle", "Paddle", "Stand-Up-Paddling"
        ],
        "windsurfing" => [ "Windsurf", "Planche à voile", "Windsurfen" ],
        "tennis_outdoor" => [ "Tennis" ],
        "strength_training" => [ "WeightTraining", "Weight Training", "Musculation", "Krafttraining" ],
        "fitness" => [
          "Workout", "Crossfit", "HIIT", "Elliptical", "StairStepper", "Stair-Stepper", "Yoga", "Pilates",
          "Entraînement", "Elliptique", "Stepper", "Training", "Crosstrainer", "Treppensteiger"
        ]
      }.freeze

      module_function

      # The catalog slug the label names, or nil.
      def slug_for(label)
        key = normalize(label)
        return nil if key.empty?

        lookup[key] || catalog_lookup[key]
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, "")
      end

      def lookup
        @lookup ||= TYPES.each_with_object({}) do |(slug, labels), result|
          labels.each { |label| result[normalize(label)] = slug }
        end.freeze
      end

      def catalog_lookup
        @catalog_lookup ||= ActivityTypeCatalog::SPORT_ALIASES.each_with_object({}) do |(slug, aliases), result|
          aliases.each { |value| result[normalize(value)] ||= slug }
        end.freeze
      end
    end
  end
end
