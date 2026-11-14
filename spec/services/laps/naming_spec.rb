# frozen_string_literal: true

require "rails_helper"

RSpec.describe Laps::Naming do
  it "clears a stale name when the toponymy no longer offers one" do
    workout = create(:workout)
    lap = create(:detected_lap, :named, workout:)
    create(:workout_toponymy, workout:, markers: [], start_place: {})

    described_class.new(workout:).call

    expect(lap.reload.name).to be_nil
  end

  it "does nothing without a toponymy" do
    workout = create(:workout)
    lap = create(:detected_lap, :named, workout:)

    described_class.new(workout:).call

    expect(lap.reload.name).to eq("Parc de la Tête d'Or")
  end
end
