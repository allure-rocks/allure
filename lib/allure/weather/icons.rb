# frozen_string_literal: true

module Allure
  module Weather
    # Condition token → Meteocons icon (PLAN_WEATHER.md §7). The files live in
    # `app/views/weather/icons`, and the server hands the map and chart
    # controllers the markup they draw; this module only names them, and
    # reads one when a caller passes the directory.
    #
    # Every icon is Bas Milius' Meteocons (MIT, the LICENSE file beside them),
    # in the monochrome style drawn in `currentColor`: the animated set in the
    # directory, the static one in its `static/` subdirectory.
    module Icons
      FALLBACK = "not-available"
      # `{ day:, night: }`, or one name when the set has no night variant
      # (rain and snow read the same after dark).
      NAMES = {
        "clear" => { day: "clear-day", night: "clear-night" },
        "mostly_clear" => { day: "mostly-clear-day", night: "mostly-clear-night" },
        "partly_cloudy" => { day: "partly-cloudy-day", night: "partly-cloudy-night" },
        "overcast" => { day: "overcast-day", night: "overcast-night" },
        "fog" => { day: "fog-day", night: "fog-night" },
        "drizzle" => "drizzle",
        "rain" => "rain",
        "heavy_rain" => "extreme-rain",
        "freezing_rain" => "sleet",
        "snow" => "snow",
        "showers" => { day: "partly-cloudy-day-rain", night: "partly-cloudy-night-rain" },
        "thunderstorm" => "thunderstorms-rain"
      }.freeze

      module_function

      # The icon base name for a condition token; `day` is true unless the
      # caller knows the sun was down.
      def name(token, day: true)
        entry = NAMES[token.to_s]
        case entry
        when Hash then day ? entry[:day] : entry[:night]
        when String then entry
        else FALLBACK
        end
      end

      # The SVG source of one icon, or the fallback's when the name is unknown.
      # Reading is the caller's business (the Vite build serves these files),
      # so the root is explicit. The files never change within a process, so
      # the read is memoized.
      def markup(name, root:)
        cache = (@markup_cache ||= {})
        cache[[ root.to_s, name ]] ||= begin
          file = File.join(root, "#{name}.svg")
          file = File.join(root, "#{FALLBACK}.svg") unless File.exist?(file)
          File.read(file)
        end
      end
    end
  end
end
