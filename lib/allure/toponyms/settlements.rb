# frozen_string_literal: true

module Allure
  module Toponyms
    # The settlement vocabulary shared by the reverse client, the enricher and
    # the candidate builder: which address levels name a settlement, and how
    # far a point may sit from a settlement centre and still read as being
    # "at" it (docs/dev/WORKOUT.md).
    module Settlements
      KINDS = %w[
        isolated_dwelling locality neighbourhood suburb hamlet village town city municipality
      ].freeze

      CENTER_DISTANCE_LIMIT = {
        "isolated_dwelling" => 400.0,
        "locality" => 500.0,
        "neighbourhood" => 500.0,
        "hamlet" => 800.0,
        "suburb" => 1_000.0,
        "village" => 1_000.0,
        "municipality" => 2_000.0,
        "town" => 2_000.0,
        "city" => 3_000.0
      }.freeze
    end
  end
end
