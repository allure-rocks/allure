# frozen_string_literal: true

module Allure
  module Together
    # Which sports two co-present recordings may carry (docs/dev/SHARED-ACTIVITIES.md).
    # Two devices on the same outing often disagree on the variant (a road
    # ride against a generic ride, a trail run against a run), so detection
    # compares curated families rather than slugs. The families are the
    # per-account sport defaults of docs/dev/WORKOUT.md without their virtual
    # members: the icon families would pair tennis with running. Any other
    # sport is its own family, and a virtual sport never matches anything.
    module SportFamilies
      FAMILIES = {
        "cycling" => %w[
          cycling cycling_road cycling_gravel cycling_electric cycling_trekking
          mountain_biking mountain_biking_electric
        ],
        "running" => %w[running trail],
        "walking" => %w[walking hiking]
      }.freeze

      module_function

      def family(slug)
        FAMILIES.each { |name, slugs| return name if slugs.include?(slug.to_s) }
        slug.to_s
      end

      def compatible?(first_slug, second_slug, first_virtual: false, second_virtual: false)
        return false if first_virtual || second_virtual

        family(first_slug) == family(second_slug)
      end
    end
  end
end
