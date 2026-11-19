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

  context "with the optional history section" do
    let(:options) { { include_history: true } }
    let(:workout) do
      create(:workout, user:, sport:, distance: 60_000.0,
                       started_at: Time.zone.parse("2026-11-17 09:00:00"))
    end

    it "adds one year of the same sport, without manual entries or later workouts" do
      create(:workout, user:, sport:, distance: 5_000.0,
                       started_at: Time.zone.parse("2026-10-01 09:00:00"))
      create(:workout, user:, sport:, distance: 7_000.0,
                       started_at: Time.zone.parse("2025-11-01 09:00:00"))
      create(:workout, user:, sport: catalog_sport("running"),
                       started_at: Time.zone.parse("2026-10-02 09:00:00"))
      create(:workout, :manual, user:, sport:, started_at: Time.zone.parse("2026-10-03 09:00:00"))
      create(:workout, user:, sport:, started_at: Time.zone.parse("2026-11-18 09:00:00"))

      history = payload[:history]

      expect(history[:window_days]).to eq(365)
      expect(history[:same_sport].map { it[:distance] }).to eq([ 5_000 ])
      expect(history[:older_same_sport]).to be(true)
      expect(history[:previous_workouts]).to eq(4)
      expect(history[:year_to_date][:workouts]).to eq(2)
      expect(history[:last_same_sport_at]).to eq("2026-10-03T09:00:00Z")
    end

    it "takes the gap from the latest workout of the sport, a typed session included" do
      create(:workout, user:, sport:, started_at: Time.zone.parse("2026-10-01 09:00:00"))
      create(:workout, :manual, user:, sport:, started_at: Time.zone.parse("2026-11-10 09:00:00"))
      create(:workout, user:, sport: catalog_sport("running"),
                       started_at: Time.zone.parse("2026-11-12 09:00:00"))

      expect(payload[:history][:last_same_sport_at]).to eq("2026-11-10T09:00:00Z")
    end

    it "counts this workout's places over the whole history and the year" do
      workout.update!(places: [ { "name" => "Chevreuse", "kind" => "start" } ])
      create(:workout, user:, sport:, started_at: Time.zone.parse("2026-10-01 09:00:00"),
                       places: [ { "name" => "Chevreuse", "kind" => "start" } ])
      create(:workout, user:, sport: catalog_sport("running"),
                       started_at: Time.zone.parse("2026-09-01 09:00:00"),
                       places: [ { "name" => "Chevreuse", "kind" => "start" } ])
      create(:workout, user:, sport:, started_at: Time.zone.parse("2025-01-01 09:00:00"),
                       places: [ { "name" => "Chevreuse", "kind" => "start" } ])

      expect(payload[:history][:places]).to eq("Chevreuse" => { seen_before: true, year_count: 2 })
    end

    it "writes no place history without a place" do
      expect(payload[:history][:places]).to eq({})
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
