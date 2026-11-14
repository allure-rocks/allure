# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sport seeds" do
  CATALOG = [
    [ "cycling", "Cycling", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "cycling_road", "Road Cycling", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "cycling_gravel", "Gravel Cycling", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "cycling_electric", "Cycling (Electric)", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "cycling_trekking", "Cycling (Trekking)", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "cycling_virtual", "Cycling (Virtual)", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "mountain_biking", "Mountain Biking", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "mountain_biking_electric", "Mountain Biking (Electric)", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "halfbike", "Halfbike", "ride", 1.0, "speed", "rpm", true, true, nil ],
    [ "inline_skating", "Inline Skating", "ride", 1.0, "speed", nil, true, false, nil ],
    [ "running", "Running", "run", 1.0, "pace", "spm", true, false, nil ],
    [ "running_virtual", "Running (Virtual)", "run", 1.0, "pace", "spm", true, false, nil ],
    [ "trail", "Trail", "run", 0.1, "pace", "spm", true, false, nil ],
    [ "walking", "Walking", "run", 0.1, "pace", "spm", true, false, nil ],
    [ "hiking", "Hiking", "hike", 0.1, "pace", "spm", true, false, nil ],
    [ "mountaineering", "Mountaineering", "hike", 0.1, "speed", "spm", true, false, nil ],
    [ "snowshoes", "Snowshoes", "hike", 0.1, "speed", "spm", true, false, nil ],
    [ "skiing_alpine", "Skiing (Alpine)", "ski", 1.0, "speed", nil, true, false, nil ],
    [ "skiing_touring", "Skiing (Touring)", "ski", 0.1, "speed", nil, true, false, nil ],
    [ "skiing_cross_country", "Skiing (Cross Country)", "ski", 0.1, "speed", nil, true, false, nil ],
    [ "snowboarding", "Snowboarding", "ski", 1.0, "speed", nil, true, false, nil ],
    [ "ice_skating", "Ice Skating", "ski", 1.0, "speed", nil, false, false, nil ],
    [ "pool_swimming", "Swimming (Pool)", "swim", 0.1, "speed", "rpm", false, false, nil ],
    [ "open_water_swimming", "Open Water Swimming", "swim", 0.1, "speed", "rpm", false, false, nil ],
    [ "swimrun", "Swimrun", "swim", 0.1, "speed", nil, true, false, nil ],
    [ "rowing", "Rowing", "swim", 1.0, "pace", nil, false, false, 500 ],
    [ "rowing_virtual", "Rowing (Virtual)", "swim", 1.0, "pace", nil, false, false, 500 ],
    [ "kayaking", "Kayaking", "swim", 1.0, "speed", nil, false, false, nil ],
    [ "kayaking_whitewater", "Kayaking (Whitewater)", "swim", 1.0, "speed", nil, true, false, nil ],
    [ "canoeing", "Canoeing", "swim", 1.0, "speed", nil, false, false, nil ],
    [ "canoeing_whitewater", "Canoeing (Whitewater)", "swim", 1.0, "speed", nil, true, false, nil ],
    [ "standup_paddleboarding", "Standup Paddleboarding", "swim", 1.0, "speed", nil, false, false, nil ],
    [ "windsurfing", "Windsurfing", "swim", 1.0, "speed", nil, true, false, nil ],
    [ "tennis_outdoor", "Tennis (Outdoor)", "run", 0.1, "speed", nil, false, false, nil ],
    [ "padel_outdoor", "Padel (Outdoor)", "run", 0.1, "speed", nil, false, false, nil ],
    [ "paragliding", "Paragliding", "other", 0.1, "speed", nil, true, false, nil ],
    [ "strength_training", "Strength Training", "other", 0.1, "speed", nil, false, false, nil ],
    [ "fitness", "Fitness", "other", 0.1, "speed", nil, false, false, nil ]
  ].freeze

  it "seeds the complete catalog idempotently" do
    load Rails.root.join("db/seeds.rb")
    first_snapshot = Sport.catalog_order.pluck(:id, :slug, :updated_at)

    load Rails.root.join("db/seeds.rb")

    expect(User.count).to eq(0)
    expect(Sport.count).to eq(38)
    expect(Sport.catalog_order.pluck(:id, :slug, :updated_at)).to eq(first_snapshot)
    expect(Sport.catalog_order.pluck(:position)).to eq((1..38).to_a)
  end

  it "matches the locked behavior groups" do
    load Rails.root.join("db/seeds.rb")

    actual = Sport.catalog_order.pluck(
      :slug, :label, :colour_group, :stopped_speed_threshold, :pace_speed_display,
      :cadence_unit, :records_elevation, :records_power, :pace_basis_metres
    ).map { |row| row.tap { it[3] = it[3].to_f } }

    expect(actual).to eq(CATALOG)
  end

  it "flags exactly the virtual sports" do
    load Rails.root.join("db/seeds.rb")

    expect(Sport.where(virtual: true).pluck(:slug))
      .to contain_exactly("cycling_virtual", "running_virtual", "rowing_virtual")
  end

  it "translates every catalog entry in French and English" do
    load Rails.root.join("db/seeds.rb")

    %i[fr en].each do |locale|
      I18n.with_locale(locale) do
        Sport.find_each { |sport| expect(sport.translated_name).to be_present }
      end
    end
  end
end
