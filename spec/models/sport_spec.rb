# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sport do
  subject(:sport) { build(:sport) }

  it { is_expected.to validate_presence_of(:slug) }
  it { is_expected.to validate_presence_of(:label) }
  it { is_expected.to validate_uniqueness_of(:slug) }
  it { is_expected.to validate_uniqueness_of(:label) }
  it { is_expected.to validate_inclusion_of(:colour_group).in_array(Allure::SportPalette::GROUPS) }
  it { is_expected.to validate_inclusion_of(:pace_speed_display).in_array(%w[pace speed pace_and_speed]) }
  it { is_expected.to validate_numericality_of(:pace_basis_metres).only_integer.is_greater_than(0).allow_nil }
  it { is_expected.to validate_numericality_of(:stopped_speed_threshold).is_greater_than_or_equal_to(0) }

  it "reports a fixed pace basis only when one is set" do
    expect(build(:sport, pace_basis_metres: 500)).to be_pace_basis
    expect(build(:sport, pace_basis_metres: nil)).not_to be_pace_basis
  end

  it "leads with power only for a virtual sport that displays speed" do
    expect(build(:sport, virtual: true, pace_speed_display: "speed")).to be_power_led
    expect(build(:sport, virtual: true, pace_speed_display: "pace")).not_to be_power_led
    expect(build(:sport, virtual: true, pace_speed_display: "pace", pace_basis_metres: 500)).not_to be_power_led
    expect(build(:sport, virtual: false, pace_speed_display: "speed")).not_to be_power_led
  end

  it "uses slugs that are safe as stable translation keys" do
    expect(build(:sport, slug: "mountain_biking_variant")).to be_valid
    expect(build(:sport, slug: "Mountain Biking")).not_to be_valid
  end

  it "orders catalog rows by position" do
    first_position = Sport.maximum(:position).to_i + 1
    later = create(:sport, position: first_position + 1)
    earlier = create(:sport, position: first_position)

    expect(described_class.catalog_order.where(id: [ earlier.id, later.id ])).to eq([ earlier, later ])
  end

  it "orders dropdowns by the localized display name, accent-insensitively" do
    cycling = catalog_sport("cycling")                     # Vélo
    road = catalog_sport("cycling_road")                   # Vélo route
    vtt = catalog_sport("mountain_biking")                 # VTT
    electric = catalog_sport("mountain_biking_electric")   # VTT électrique

    ordered = described_class.alphabetical(
      described_class.where(slug: %w[cycling cycling_road mountain_biking mountain_biking_electric])
    )

    expect(ordered).to eq([ cycling, road, vtt, electric ])
  end

  it "enforces enum-like values in the database" do
    sport = create(:sport)
    expect { sport.update_column(:colour_group, "unknown") }
      .to raise_error(ActiveRecord::StatementInvalid, /sports_colour_group/)
  end

  it "enforces non-negative thresholds in the database" do
    sport = create(:sport)
    expect { sport.update_column(:stopped_speed_threshold, -0.1) }
      .to raise_error(ActiveRecord::StatementInvalid, /sports_stopped_speed_threshold/)
  end

  it "enforces a positive pace basis in the database" do
    sport = create(:sport)
    expect { sport.update_column(:pace_basis_metres, 0) }
      .to raise_error(ActiveRecord::StatementInvalid, /sports_pace_basis_metres/)
  end

  it "treats a persisted slug as immutable" do
    sport = create(:sport)
    expect { sport.update!(slug: "another_sport") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
  end
end
