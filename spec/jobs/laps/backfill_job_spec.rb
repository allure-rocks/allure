# frozen_string_literal: true

require "rails_helper"

RSpec.describe Laps::BackfillJob do
  it "rebuilds detected laps for existing workouts" do
    workout = create(:workout)
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1)

    described_class.perform_now

    expect(workout.detected_laps.where(source: "pause").count).to eq(2)
  end
end
