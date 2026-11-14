# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutElevation do
  subject(:elevation) { build(:workout_elevation) }

  it { is_expected.to belong_to(:workout) }
  it { is_expected.to validate_uniqueness_of(:workout_id) }

  it do
    is_expected.to define_enum_for(:status)
      .with_values(described_class::STATUSES.index_with(&:itself))
      .backed_by_column_of_type(:string)
  end

  it "requires an array of samples" do
    elevation.samples = {}

    expect(elevation).not_to be_valid
    expect(elevation.errors).to include(:samples)
  end

  it "requires a positive algorithm version and a non-negative request count" do
    elevation.algorithm_version = 0
    elevation.requests_count = -1

    expect(elevation).not_to be_valid
    expect(elevation.errors).to include(:algorithm_version, :requests_count)
  end
end
