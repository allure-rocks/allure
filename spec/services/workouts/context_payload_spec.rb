# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ContextPayload do
  subject(:payload) { described_class.new(workout, user:).call(**options) }

  let(:options) { {} }
  let(:user) { create(:user) }
  let(:sport) { catalog_sport("cycling") }
  let(:workout) { create(:workout, user:, sport:) }

  it "builds the owner-only sections in order" do
    expect(payload.keys).to eq(
      %i[account units workout equipment records_set laps splits best_efforts segment_efforts training]
    )
    expect(payload[:account]).to eq(unit_system: "metric", time_zone: "Europe/Paris", week_start: "monday")
    expect(payload[:units]).to eq(described_class::UNITS)
    expect(payload[:workout]).to include(id: workout.to_param, sport_details: include(slug: "cycling"))
    expect(payload[:laps]).to include(:recorded, :detected, :truncated_sources)
    expect(payload[:splits]).to include(:distance, :rows, :truncated)
    expect(payload[:training]).to include(:window_days, :same_sport, :all_sports, :recent_same_sport)
    expect(payload[:training][:window_days]).to eq(28)
  end

  context "when the optional sections are switched off" do
    let(:options) do
      { include_laps: false, include_splits: false, include_efforts: false, include_training: false }
    end

    it "keeps only the always-present sections" do
      expect(payload.keys).to eq(%i[account units workout equipment records_set])
    end
  end

  it "serves the compact row of list_workouts to the same owner" do
    row = described_class.summary(workout, user)

    expect(row).to include(id: workout.to_param, sport: "cycling", origin: "import")
    expect(row[:started_at]).to eq(workout.started_at.utc.iso8601)
    expect(row[:local_start]).to eq(workout.started_at.in_time_zone("Europe/Paris").iso8601)
    expect(row[:average_pace]).to be_a(Integer)
  end
end
