# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutToponymy do
  subject(:toponymy) { build(:workout_toponymy) }

  it { is_expected.to belong_to(:workout) }
  it { is_expected.to validate_uniqueness_of(:workout_id) }
  it do
    is_expected.to define_enum_for(:status)
      .with_values(described_class::STATUSES.index_with(&:itself))
      .backed_by_column_of_type(:string)
  end

  it "requires array and object JSON shapes" do
    toponymy.samples = {}
    toponymy.markers = {}
    toponymy.places = {}
    toponymy.start_place = []
    toponymy.finish_place = []

    expect(toponymy).not_to be_valid
    expect(toponymy.errors).to include(:samples, :markers, :places, :start_place, :finish_place)
  end

  it "requires a non-negative places algorithm version" do
    toponymy.places_algorithm_version = -1

    expect(toponymy).not_to be_valid
    expect(toponymy.errors).to include(:places_algorithm_version)
  end

  it "accepts dense sample counts" do
    toponymy.sampled_points_count = 1_000

    expect(toponymy).to be_valid
  end
end
