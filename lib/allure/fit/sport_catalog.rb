# frozen_string_literal: true

module Allure
  module Fit
    # Translates a FIT `sport`/`sub_sport` pair into an activity alias that
    # already exists in `Allure::ActivityTypeCatalog::SPORT_ALIASES`.
    #
    # Deliberately does not resolve a `Sport#slug` itself. Emitting an alias
    # and letting `Allure::ActivityDetector` resolve it keeps one detection
    # path for every import format, so alias, normalization, and ambiguity
    # rules cannot drift between GPX and FIT.
    #
    # Sports outside the Allure catalog return nil and the import falls back
    # to the user-selected sport, following the catalog's stated policy that
    # unsupported activities are left out rather than silently misclassified.
    module SportCatalog
      # Matched first. Only pairs whose meaning differs from the bare sport
      # are listed; anything else falls through to SPORT_ALIASES.
      SUB_SPORT_ALIASES = {
        %i[running trail] => "trail running",
        %i[running street] => "running",
        %i[running track] => "running",
        %i[running treadmill] => "virtual run",
        %i[running indoor_running] => "virtual run",
        %i[running virtual_activity] => "virtual run",
        %i[cycling road] => "road cycling",
        %i[cycling mountain] => "mountain biking",
        %i[cycling downhill] => "mountain biking",
        %i[cycling gravel_cycling] => "gravel",
        %i[cycling mixed_surface] => "gravel",
        %i[cycling e_bike_mountain] => "emtb",
        %i[cycling e_bike_fitness] => "ebike",
        %i[cycling indoor_cycling] => "indoor cycling",
        %i[cycling spin] => "indoor cycling",
        %i[cycling virtual_activity] => "virtual cycling",
        %i[e_biking e_bike_mountain] => "emtb",
        # The `fitness_equipment` sport is what indoor machines and several
        # rowing/cycling apps write; its indoor sub-sports are unambiguous.
        %i[fitness_equipment indoor_rowing] => "virtual rowing",
        %i[fitness_equipment indoor_cycling] => "indoor cycling",
        %i[rowing indoor_rowing] => "virtual rowing",
        %i[alpine_skiing backcountry] => "ski touring",
        %i[swimming lap_swimming] => "pool swimming",
        %i[swimming open_water] => "open water swimming",
        %i[hiking trail] => "hiking",
        %i[walking casual_walking] => "walking",
        %i[walking speed_walking] => "walking",
        # An indoor session with no distance at all (PLAN_NO_GPS.md §3.3):
        # the gym machines whose sub-sport names the activity.
        %i[training strength_training] => "strength training",
        %i[training cardio_training] => "fitness",
        %i[training hiit] => "fitness",
        %i[training flexibility_training] => "fitness",
        %i[training yoga] => "fitness",
        %i[training pilates] => "fitness",
        %i[fitness_equipment elliptical] => "fitness",
        %i[fitness_equipment stair_climbing] => "fitness"
      }.freeze

      # The commute flag is orthogonal to the sport: `commuting` names a
      # purpose, not a speed or power profile. The parser records it as a track
      # hint and the importer persists it beside the detected sport.
      COMMUTE_PAIRS = [ %i[cycling commuting], %i[e_biking commuting] ].freeze

      SPORT_ALIASES = {
        running: "running",
        cycling: "cycling",
        e_biking: "ebike",
        swimming: "pool swimming",
        walking: "walking",
        hiking: "hiking",
        cross_country_skiing: "cross country skiing",
        alpine_skiing: "alpine skiing",
        snowboarding: "snowboarding",
        rowing: "rowing",
        mountaineering: "mountaineering",
        snowshoeing: "snowshoeing",
        inline_skating: "inline skating",
        ice_skating: "ice skating",
        stand_up_paddleboarding: "standup paddleboarding",
        kayaking: "kayaking",
        windsurfing: "windsurfing",
        tennis: "tennis",
        # A bare `training` session writes nothing more specific; so does a
        # `fitness_equipment` file without an indoor sub-sport.
        training: "fitness",
        fitness_equipment: "fitness"
      }.freeze

      module_function

      # Returns an alias string, or nil when the activity has no Allure
      # equivalent. `sport` and `sub_sport` are profile symbols.
      def alias_for(sport:, sub_sport: nil)
        return nil if sport.nil?

        SUB_SPORT_ALIASES.fetch([ sport, sub_sport ]) { SPORT_ALIASES[sport] }
      end

      def commute?(sport:, sub_sport: nil)
        COMMUTE_PAIRS.include?([ sport, sub_sport ])
      end
    end
  end
end
