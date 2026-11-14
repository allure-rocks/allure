# frozen_string_literal: true

module Allure
  module ActivityTypeCatalog
    # External activity names are deliberately aliases of the stable Allure
    # sport slugs. Unsupported activities are left out and use the import
    # fallback rather than being silently misclassified.
    SPORT_ALIASES = {
      "cycling" => [
        "cycling", "cycling sport", "cycling_sport", "ride", "bike", "biking",
        "bicycle", "velomobile", "handcycle", "commute", "commuting",
        "transport cycling", "utility biking", "cyclisme", "vélo", "velo"
      ],
      "cycling_road" => [
        "cycling_road", "road cycling", "road_cycling", "road bike", "road biking",
        "roadbikeride", "roadride"
      ],
      "cycling_gravel" => [
        "cycling_gravel", "gravel", "gravel ride", "gravel_ride", "gravelride",
        "gravel biking", "gravel cycling", "gravelcycling", "mixed surface",
        "mixed_surface"
      ],
      "cycling_electric" => [
        "cycling_electric", "e bike", "e_bike", "ebike", "ebikeride", "ebike ride",
        "electric bike", "electric bicycle", "electric cycling", "pedelec",
        "vélo électrique", "velo electrique"
      ],
      "cycling_trekking" => [
        "cycling_trekking", "cycling trekking", "trekking cycling", "cycle touring",
        "bike touring", "touring", "touring cycling", "cycling touring"
      ],
      "cycling_virtual" => [
        "cycling_virtual", "virtual cycling", "virtual ride", "virtualride",
        "indoor cycling", "indoor bike", "indoor ride"
      ],
      "mountain_biking" => [
        "mountain_biking", "mountain biking", "mountain bike", "mountainbike",
        "mountainbiking", "mountain bike ride", "mountainbikeride", "mtb", "btt",
        "vtt", "cross country mtb", "cross_country_mtb", "cross country mountain bike"
      ],
      "mountain_biking_electric" => [
        "mountain_biking_electric", "mountain biking electric", "electric mountain bike",
        "electric mountain biking", "e mountain bike", "e_mountain_bike", "e mountain bike ride",
        "emountainbikeride", "emtb", "e mtb", "e_mtb"
      ],
      "hiking" => [
        "hiking", "hike", "mountain hiking", "trekking", "trek", "backpacking",
        "randonnée", "randonnee", "randonnée pédestre", "rando", "walking hike"
      ],
      "running" => [
        "running", "run", "jogging", "road running", "road_running",
        "course", "footing", "course à pied", "course a pied"
      ],
      "running_virtual" => [
        "running_virtual", "virtual run", "virtual_run", "virtualrun",
        "treadmill run", "treadmill_running", "indoor running", "indoor_running"
      ],
      "trail" => [
        "trail", "trail running", "trail_running", "trailrun", "trail run", "trailrunning"
      ],
      "walking" => [
        "walking", "walk", "nordic walking", "nordic_walking", "marche", "pedestrian",
        "on foot", "on_foot", "marche à pied", "marche a pied", "foot"
      ],
      "skiing_alpine" => [
        "skiing_alpine", "alpine skiing", "alpine_ski", "alpineski", "alpine ski",
        "downhill skiing", "downhill_skiing", "ski", "skiing", "ski alpin"
      ],
      "skiing_touring" => [
        "skiing_touring", "ski touring", "ski_touring", "skitouring", "backcountry ski",
        "backcountry_ski", "backcountryski", "backcountry skiing", "ski de randonnée",
        "ski de randonnee"
      ],
      "skiing_cross_country" => [
        "skiing_cross_country", "cross country skiing", "cross_country_skiing",
        "cross country ski", "crosscountryski", "nordic skiing", "nordic_ski", "nordicski",
        "roller ski", "roller_ski", "rollerski", "ski de fond"
      ],
      "rowing" => [ "rowing", "row", "aviron" ],
      "rowing_virtual" => [
        "rowing_virtual", "virtual rowing", "virtual_row", "virtualrow",
        "indoor rowing", "indoor_rowing"
      ],
      "snowshoes" => [ "snowshoes", "snowshoe", "snowshoeing", "snow_shoe" ],
      "snowboarding" => [ "snowboarding", "snowboard", "snow board" ],
      "mountaineering" => [ "mountaineering", "mountain climbing", "alpinism", "alpinisme" ],
      "paragliding" => [ "paragliding", "paraglider", "parapente" ],
      "pool_swimming" => [
        "pool_swimming", "pool swimming", "pool swim", "poolswim",
        "lap swimming", "lap_swimming", "indoor swimming", "natation en piscine",
        "natation piscine"
      ],
      "open_water_swimming" => [
        "open water swimming", "open_water_swimming", "open water swim", "openwater swim",
        "openwaterswim",
        "swimming", "swim", "swimming outdoor", "swimming_outdoor", "natation",
        "natation en eau libre", "natation eau libre"
      ],
      "swimrun" => [ "swimrun", "swim run", "swim_run" ],
      "kayaking" => [ "kayaking", "kayak" ],
      "kayaking_whitewater" => [ "whitewater kayaking", "kayaking whitewater", "kayaking_whitewater" ],
      "canoeing" => [ "canoeing", "canoe" ],
      "canoeing_whitewater" => [ "whitewater canoeing", "canoeing whitewater", "canoeing_whitewater" ],
      "windsurfing" => [ "windsurfing", "windsurf", "wind surf" ],
      "standup_paddleboarding" => [
        "standup paddleboarding", "stand up paddleboarding", "stand_up_paddling",
        "standuppaddling", "standup paddle", "standuppaddle", "sup", "paddleboarding",
        "paddle", "stand up paddle"
      ],
      "tennis_outdoor" => [ "tennis", "outdoor tennis", "tennis outdoor", "tennis_outdoor" ],
      "padel_outdoor" => [ "padel", "outdoor padel", "padel outdoor", "padel_outdoor" ],
      "ice_skating" => [ "ice skating", "ice_skate", "iceskate", "ice_skating" ],
      "strength_training" => [
        "strength_training", "strength training", "strength", "weights", "weight training",
        "weight_training", "weightlifting", "weight lifting", "gym", "musculation",
        "renforcement musculaire", "halterophilie"
      ],
      "fitness" => [
        "fitness", "workout", "cardio", "cardio training", "cardio_training", "hiit",
        "interval training", "aerobics", "elliptical", "elliptical_training",
        "stair climbing", "stair_climbing", "stairclimbing", "rowing machine",
        "flexibility", "flexibility_training", "yoga", "pilates", "gymnastics",
        "gymnastique", "fitness equipment", "fitness_equipment"
      ],
      "inline_skating" => [
        "inline skating", "inline skate", "inline_skate", "inlineskate", "rollerblading",
        "rollerblading"
      ]
    }.freeze
  end
end
