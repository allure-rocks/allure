# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Heart-rate jobs" do
  let(:user) { create(:user) }

  def recording_with_heart_rate(owner = user)
    workout = create(:workout, user: owner)
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.07, "lon" => 6.40, "hr" => 120 },
      { "t" => 20, "d" => 250.0, "lat" => 45.071, "lon" => 6.40, "hr" => 175 },
      { "t" => 40, "d" => 500.0, "lat" => 45.072, "lon" => 6.40, "hr" => 175 }
    ])
    workout
  end

  describe HeartRates::BackfillJob do
    it "rebuilds every stale recording and leaves credit rows and manual entries alone" do
      workout = recording_with_heart_rate
      manual = create(:workout, :manual, user:)

      expect(described_class.pending_scope).to include(workout)
      expect(described_class.pending_scope).not_to include(manual)

      described_class.perform_now

      expect(workout.reload.heart_rate.sampled_seconds).to eq(40)
      expect(described_class.pending_scope).to be_empty
    end

    it "resumes itself after a full batch" do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      recording_with_heart_rate
      recording_with_heart_rate

      expect { described_class.perform_now }.to have_enqueued_job(described_class)
    end
  end

  describe HeartRates::RezoneJob do
    it "re-slices stale rows under the new zones without reading a point, then clears them" do
      workout = recording_with_heart_rate
      HeartRates::Rebuild.new(workout:).call
      expect(workout.reload.heart_rate.zone_seconds).to be_nil

      user.update!(max_heart_rate: 190)
      described_class.perform_now(user)

      row = workout.heart_rate.reload
      expect(row.zone_seconds).to eq([ 0, 20, 0, 0, 20 ])
      expect(row.zones_fingerprint).to eq(user.heart_rate_zones.fingerprint)

      user.update!(max_heart_rate: nil)
      described_class.perform_now(user)

      expect(row.reload.zone_seconds).to be_nil
      expect(row.load).to be_nil
    end

    it "never touches another account's rows" do
      other = create(:user)
      foreign = recording_with_heart_rate(other)
      HeartRates::Rebuild.new(workout: foreign).call

      user.update!(max_heart_rate: 190)
      described_class.perform_now(user)

      expect(foreign.heart_rate.reload.zone_seconds).to be_nil
    end
  end

  describe Workouts::UserBackfillJob do
    it "counts and rebuilds the account's stale histograms" do
      workout = recording_with_heart_rate

      expect(described_class.counts(user)).to include("heart_rate" => 1)

      described_class.perform_now(user.id, "heart_rate")

      expect(workout.reload.heart_rate).to be_present
      expect(described_class.counts(user)).to include("heart_rate" => 0)
    end
  end
end
