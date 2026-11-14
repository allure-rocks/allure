# frozen_string_literal: true

# One personal record: the winning workout per (user, sport, type), recomputed
# by `Records::RecomputeService` on workout create, metric/sport change, and
# delete. The value is stored in the type's SI base unit; presentation converts
# to viewer units. No ShortUUID and no show route: records are read on the
# owner's grouped `/me/records` page, with an opt-in label/value projection on
# the local member profile (PLAN_M3.md §8). See sections 6.2 and 7.4; `MC`
# (biggest climb) reads the detected climbs per PLAN_BEST_EFFORTS.md.
class Record < ApplicationRecord
  TYPES = %w[AP AS BP FD HA LD MS MC].freeze

  # Record type => the workout metric it derives from, used to decide whether a
  # profile may publish the marker. `MC` reads a detected climb's ascent, so it
  # has no summary tile of its own (`TILE_METRIC_KEYS`).
  METRIC_KEYS = {
    "AP" => "average_pace",
    "AS" => "average_speed",
    "BP" => "best_pace",
    "FD" => "distance",
    "HA" => "ascent",
    "LD" => "moving_time",
    "MS" => "max_speed",
    "MC" => "ascent"
  }.freeze
  TILE_METRIC_KEYS = METRIC_KEYS.reject { |type, _metric| type == "MC" }.freeze

  belongs_to :user
  belongs_to :sport
  belongs_to :workout, optional: true

  validates :record_type, inclusion: { in: TYPES }, uniqueness: { scope: %i[user_id sport_id] }
  validates :value, numericality: { greater_than_or_equal_to: 0 }
  validates :workout_started_at, presence: true

  # Read-time display filtering shared by `/me/records` and the workout badge:
  # a type the sport cannot express is never shown, even though its row exists.
  def self.visible_type?(record_type, sport)
    case record_type
    when "HA", "MC" then sport.records_elevation
    when "AS", "MS" then sport.pace_speed_display != "pace"
    when "AP", "BP" then sport.pace_speed_display != "speed"
    else true
    end
  end
end
