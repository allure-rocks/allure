# frozen_string_literal: true

module CatalogSports
  ATTRIBUTES = {
    "cycling" => {
      label: "Cycling",
      colour_group: "ride",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "speed",
      cadence_unit: "rpm",
      records_elevation: true,
      records_power: true
    },
    "running" => {
      label: "Running",
      colour_group: "run",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "pace",
      cadence_unit: "spm",
      records_elevation: true,
      records_power: false
    },
    "trail" => {
      label: "Trail",
      colour_group: "run",
      stopped_speed_threshold: 0.1,
      pace_speed_display: "pace",
      cadence_unit: "spm",
      records_elevation: true,
      records_power: false
    },
    "running_virtual" => {
      label: "Running (Virtual)",
      colour_group: "run",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "pace",
      cadence_unit: "spm",
      records_elevation: true,
      records_power: false,
      virtual: true
    },
    "cycling_virtual" => {
      label: "Cycling (Virtual)",
      colour_group: "ride",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "speed",
      cadence_unit: "rpm",
      records_elevation: true,
      records_power: true,
      virtual: true
    },
    "rowing_virtual" => {
      label: "Rowing (Virtual)",
      colour_group: "swim",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "pace",
      pace_basis_metres: 500,
      cadence_unit: nil,
      records_elevation: false,
      records_power: false,
      virtual: true
    },
    "hiking" => {
      label: "Hiking",
      colour_group: "hike",
      stopped_speed_threshold: 0.1,
      pace_speed_display: "pace",
      cadence_unit: "spm",
      records_elevation: true,
      records_power: false
    },
    "walking" => {
      label: "Walking",
      colour_group: "run",
      stopped_speed_threshold: 0.1,
      pace_speed_display: "pace",
      cadence_unit: "spm",
      records_elevation: true,
      records_power: false
    },
    "tennis_outdoor" => {
      label: "Tennis (Outdoor)",
      colour_group: "run",
      stopped_speed_threshold: 0.1,
      pace_speed_display: "speed",
      cadence_unit: nil,
      records_elevation: false,
      records_power: false
    },
    "cycling_road" => {
      label: "Road Cycling",
      colour_group: "ride",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "speed",
      cadence_unit: "rpm",
      records_elevation: true,
      records_power: true
    },
    "mountain_biking" => {
      label: "Mountain Biking",
      colour_group: "ride",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "speed",
      cadence_unit: "rpm",
      records_elevation: true,
      records_power: true
    },
    "mountain_biking_electric" => {
      label: "Mountain Biking (Electric)",
      colour_group: "ride",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "speed",
      cadence_unit: "rpm",
      records_elevation: true,
      records_power: true
    },
    "skiing_alpine" => {
      label: "Skiing (Alpine)",
      colour_group: "ski",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "speed",
      cadence_unit: nil,
      records_elevation: true,
      records_power: false
    },
    "rowing" => {
      label: "Rowing",
      colour_group: "swim",
      stopped_speed_threshold: 1.0,
      pace_speed_display: "pace",
      pace_basis_metres: 500,
      cadence_unit: nil,
      records_elevation: false,
      records_power: false
    },
    # The duration-only indoor catch-all (docs/dev/NO-GPS.md), the Allure
    # equivalent of a bare FIT `fitness_equipment` session.
    "fitness" => {
      label: "Fitness",
      colour_group: "other",
      stopped_speed_threshold: 0.1,
      pace_speed_display: "speed",
      cadence_unit: nil,
      records_elevation: false,
      records_power: false
    }
  }.freeze

  def catalog_sport(slug)
    attributes = ATTRIBUTES.fetch(slug)
    Sport.find_or_create_by!(slug:) do |sport|
      sport.assign_attributes(
        **attributes,
        active: true,
        position: Sport.maximum(:position).to_i + 1
      )
    end
  end
end

RSpec.configure do |config|
  config.include CatalogSports
end
