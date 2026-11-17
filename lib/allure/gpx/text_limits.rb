# frozen_string_literal: true

module Allure
  module Gpx
    # The longest text a parsed file may hand on (docs/dev/WORKOUT.md). Every
    # format builds the shared `Track` and `Lap` values, which clip here, so a
    # file's text is bounded once whatever reads it: the title and the
    # description at the workout's own validation limits, the device name and
    # the lap trigger well within what any page shows.
    module TextLimits
      CREATOR = 255
      NAME = 255
      DESCRIPTION = 10_000
      LAP_TRIGGER = 32

      module_function

      def clip(value, limit)
        return value unless value.is_a?(String) && value.length > limit

        value[0, limit]
      end
    end
  end
end
