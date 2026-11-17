# frozen_string_literal: true

# Idempotent. Safe to re-run. Reference catalogs are seeded in every
# environment. The demo accounts and their activities are seeded only in
# development, by db/seeds/development.rb. Production and preproduction
# databases therefore stay free of bootstrap credentials: their `db:seed` runs
# the reference section only.

# 36 active sports grouped by icon family. `cycling` is the generic ride
# catch-all (the old `cycling_sport`); `cycling_road` is explicit-only. The
# former `cycling_transport` was deleted: the per-workout `commute` flag
# replaces it (migration ReworkCyclingCatalog).
sport_rows = [
  [ "cycling", "Cycling", "ride", 1.0, "speed", "rpm", true, true ],
  [ "cycling_road", "Road Cycling", "ride", 1.0, "speed", "rpm", true, true ],
  [ "cycling_gravel", "Gravel Cycling", "ride", 1.0, "speed", "rpm", true, true ],
  [ "cycling_electric", "Cycling (Electric)", "ride", 1.0, "speed", "rpm", true, true ],
  [ "cycling_trekking", "Cycling (Trekking)", "ride", 1.0, "speed", "rpm", true, true ],
  [ "cycling_virtual", "Cycling (Virtual)", "ride", 1.0, "speed", "rpm", true, true ],
  [ "mountain_biking", "Mountain Biking", "ride", 1.0, "speed", "rpm", true, true ],
  [ "mountain_biking_electric", "Mountain Biking (Electric)", "ride", 1.0, "speed", "rpm", true, true ],
  [ "halfbike", "Halfbike", "ride", 1.0, "speed", "rpm", true, true ],
  [ "inline_skating", "Inline Skating", "ride", 1.0, "speed", nil, true, false ],
  [ "running", "Running", "run", 1.0, "pace", "spm", true, false ],
  [ "running_virtual", "Running (Virtual)", "run", 1.0, "pace", "spm", true, false ],
  [ "trail", "Trail", "run", 0.1, "pace", "spm", true, false ],
  [ "walking", "Walking", "run", 0.1, "pace", "spm", true, false ],
  [ "hiking", "Hiking", "hike", 0.1, "pace", "spm", true, false ],
  [ "mountaineering", "Mountaineering", "hike", 0.1, "speed", "spm", true, false ],
  [ "snowshoes", "Snowshoes", "hike", 0.1, "speed", "spm", true, false ],
  [ "skiing_alpine", "Skiing (Alpine)", "ski", 1.0, "speed", nil, true, false ],
  [ "skiing_touring", "Skiing (Touring)", "ski", 0.1, "speed", nil, true, false ],
  [ "skiing_cross_country", "Skiing (Cross Country)", "ski", 0.1, "speed", nil, true, false ],
  [ "snowboarding", "Snowboarding", "ski", 1.0, "speed", nil, true, false ],
  [ "ice_skating", "Ice Skating", "ski", 1.0, "speed", nil, false, false ],
  [ "pool_swimming", "Swimming (Pool)", "swim", 0.1, "speed", "rpm", false, false ],
  [ "open_water_swimming", "Open Water Swimming", "swim", 0.1, "speed", "rpm", false, false ],
  [ "swimrun", "Swimrun", "swim", 0.1, "speed", nil, true, false ],
  [ "rowing", "Rowing", "swim", 1.0, "pace", nil, false, false, 500 ],
  [ "rowing_virtual", "Rowing (Virtual)", "swim", 1.0, "pace", nil, false, false, 500 ],
  [ "kayaking", "Kayaking", "swim", 1.0, "speed", nil, false, false ],
  [ "kayaking_whitewater", "Kayaking (Whitewater)", "swim", 1.0, "speed", nil, true, false ],
  [ "canoeing", "Canoeing", "swim", 1.0, "speed", nil, false, false ],
  [ "canoeing_whitewater", "Canoeing (Whitewater)", "swim", 1.0, "speed", nil, true, false ],
  [ "standup_paddleboarding", "Standup Paddleboarding", "swim", 1.0, "speed", nil, false, false ],
  [ "windsurfing", "Windsurfing", "swim", 1.0, "speed", nil, true, false ],
  [ "tennis_outdoor", "Tennis (Outdoor)", "run", 0.1, "speed", nil, false, false ],
  [ "padel_outdoor", "Padel (Outdoor)", "run", 0.1, "speed", nil, false, false ],
  [ "paragliding", "Paragliding", "other", 0.1, "speed", nil, true, false ],
  # Indoor sessions without a distance at all (docs/dev/NO-GPS.md): a
  # strength workout and the generic fitness catch-all.
  [ "strength_training", "Strength Training", "other", 0.1, "speed", nil, false, false ],
  [ "fitness", "Fitness", "other", 0.1, "speed", nil, false, false ]
].freeze

target_slugs = sport_rows.map(&:first)
target_positions = sport_rows.each_with_index.to_h { |row, index| [ row.first, index + 1 ] }
target_range = target_positions.values.to_set

# The unique index on `position` forbids shifting rows one by one. Every row
# outside the target set that still occupies a wanted position is moved out of
# range first, and renumbering only happens when the catalog actually changed,
# so a re-run writes nothing (spec/seeds/sports_spec.rb locks this).
needs_shift = Sport.where.not(slug: target_slugs).where(position: target_range).exists? ||
  Sport.where(slug: target_slugs).any? { |sport| sport.position != target_positions.fetch(sport.slug) }
Sport.update_all("position = position + 10000") if needs_shift

# A virtual sport records an activity in a rendered world (docs/dev/VIRTUAL-PLATFORMS.md):
# geocoding is meaningless for it, and its place is named from the platform's
# venue catalog instead.
virtual_slugs = %w[cycling_virtual running_virtual rowing_virtual].to_set

sport_rows.each_with_index do |row, index|
  slug, label, colour_group, threshold, display, cadence, elevation, power, pace_basis = row
  sport = Sport.find_or_initialize_by(slug:)
  sport.assign_attributes(
    label:,
    colour_group:,
    stopped_speed_threshold: threshold,
    pace_speed_display: display,
    pace_basis_metres: pace_basis,
    cadence_unit: cadence,
    records_elevation: elevation,
    records_power: power,
    virtual: virtual_slugs.include?(slug),
    active: true,
    position: index + 1
  )
  sport.save! if sport.changed?
end

equipment_type_rows = [
  [ "bike", "Bike" ],
  [ "bike_trainer", "Bike trainer" ],
  [ "board", "Board" ],
  [ "kayak_boat", "Kayak" ],
  [ "misc", "Miscellaneous" ],
  [ "paddle", "Paddle" ],
  [ "racket", "Racket" ],
  [ "skates", "Skates" ],
  [ "shoes", "Shoes" ],
  [ "skis", "Skis" ],
  [ "snowshoes", "Snowshoes" ]
].freeze

equipment_type_rows.each do |slug, label|
  equipment_type = EquipmentType.find_or_initialize_by(slug:)
  equipment_type.assign_attributes(label:, is_active: true)
  equipment_type.save! if equipment_type.changed?
end

# Development demo dataset (db/seeds/development.rb). Production runs
# `db:prepare db:seed` with RAILS_ENV=production and only gets the reference
# catalogs above; the guard is `Rails.env.development?` because `.local?`
# would also match test and break spec/seeds/sports_spec.rb's "no users"
# assertion.
require_relative "seeds/development" if Rails.env.development?
