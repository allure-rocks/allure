# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutPlaceName do
  subject(:place_name) { build(:workout_place_name) }

  it { is_expected.to belong_to(:workout) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(120) }
  it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }

  it "requires a unique position within its workout" do
    workout = create(:workout)
    create(:workout_place_name, workout:, position: 0)

    expect(build(:workout_place_name, workout:, position: 0)).not_to be_valid
  end

  it "is destroyed with its workout" do
    place_name = create(:workout_place_name)

    place_name.workout.destroy!

    expect(described_class.where(id: place_name.id)).not_to exist
  end
end
