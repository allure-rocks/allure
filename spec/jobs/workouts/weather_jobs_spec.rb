# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Weather scheduling", :weather do
  include ActiveJob::TestHelper

  let(:user) { create(:user, weather_enrichment_enabled: true) }

  describe Workouts::WeatherRefresh do
    it "marks the row pending and enqueues the paced job" do
      workout = weather_workout(user:)

      expect { described_class.new(workout:).call }.to have_enqueued_job(Workouts::EnrichWeatherJob).with(workout)
      expect(workout.weather).to be_pending
    end

    it "asks nothing for a manual entry, a credit row or a positionless recording" do
      manual = create(:workout, :manual, user:)
      positionless = create(:workout, :unpositioned, user:)

      expect(described_class.new(workout: manual).call).to be_nil
      expect(described_class.new(workout: positionless).call).to be_nil
      expect(Workouts::EnrichWeatherJob).not_to have_been_enqueued
    end
  end

  describe Workouts::EnrichWeatherJob do
    it "stores the weather and nudges automatic publishing" do
      stub_open_meteo
      workout = weather_workout(user:)
      allow(Workouts::AutoPublishJob).to receive(:nudge)

      described_class.perform_now(workout)

      expect(workout.reload.weather).to be_ready
      expect(Workouts::AutoPublishJob).to have_received(:nudge).with(workout)
    end
  end

  describe Workouts::BackfillWeatherJob do
    it "covers consenting accounts' workouts without current weather" do
      missing = weather_workout(user:)
      current = weather_workout(user:)
      create(:workout_weather, workout: current)
      stale = weather_workout(user:)
      create(:workout_weather, workout: stale, analysis_version: 0)
      weather_workout(user: create(:user))

      expect(described_class.pending_scope).to contain_exactly(missing, stale)

      described_class.perform_now
      expect(missing.reload.weather).to be_pending
    end
  end

  describe Workouts::WeatherRecoveryJob do
    it "reschedules stuck and recently failed rows" do
      stuck = weather_workout(user:)
      create(:workout_weather, workout: stuck, status: "pending", updated_at: 3.hours.ago)
      failed = weather_workout(user:)
      create(:workout_weather, workout: failed, status: "failed", updated_at: 7.hours.ago, created_at: 1.day.ago)
      old_failure = weather_workout(user:)
      create(:workout_weather, workout: old_failure, status: "failed", updated_at: 7.hours.ago, created_at: 3.days.ago)

      expect(described_class.pending_scope).to contain_exactly(stuck, failed)
    end
  end

  describe "import" do
    it "schedules the weather of a consenting account's positioned workout" do
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(Rails.root.join("spec/fixtures/gpx/multi_segment.gpx")),
        filename: "multi_segment.gpx", type: "application/gpx+xml"
      )

      result = Workouts::Importer.new(user:, sport: catalog_sport("cycling"), uploaded_file: file).call

      expect(result.workout.weather).to be_pending
    end
  end
end
