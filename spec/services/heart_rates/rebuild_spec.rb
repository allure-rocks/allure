# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartRates::Rebuild do
  let(:user) { create(:user, max_heart_rate: 190) }
  let(:workout) { create(:workout, user:) }

  def add_segment(heart_rates)
    points = heart_rates.each_with_index.map do |bpm, index|
      { "t" => index * 10, "d" => index * 40.0, "lat" => 45.07 + (index * 0.0001), "lon" => 6.40 }
        .tap { it["hr"] = bpm if bpm }
    end
    create(:track_segment, workout:, points:)
  end

  it "stores the histogram, slices the owner's zones and stamps the marker" do
    add_segment([ 100, 100, 150, 180, 180 ])

    described_class.new(workout:).call
    row = workout.reload.heart_rate

    expect(row.sampled_seconds).to eq(40)
    expect(row.recorded_seconds).to eq(40)
    expect(row.covered_seconds).to eq(40)
    expect(row).not_to be_sparse
    expect(row.zone_seconds).to eq([ 20, 0, 10, 0, 10 ])
    expect(row.zones_fingerprint).to eq(user.heart_rate_zones.fingerprint)
    expect(row.load.to_f).to eq(Allure::HeartRate::Load.edwards(row.histogram, user.heart_rate_zones))
    expect(workout.heart_rate_version).to eq(Allure::HeartRate::Histogram::VERSION)
  end

  it "leaves the zone columns empty without a profile" do
    user.update!(max_heart_rate: nil)
    add_segment([ 120, 120 ])

    described_class.new(workout:).call

    expect(workout.reload.heart_rate.zone_seconds).to be_nil
    expect(workout.heart_rate.load).to be_nil
  end

  it "stamps without a row when nothing was recorded, and removes a former row" do
    segment = add_segment([ 120, 120 ])
    described_class.new(workout:).call
    segment.update!(points: segment.points.map { it.except("hr") })

    described_class.new(workout:).call

    expect(WorkoutHeartRate.where(workout:)).to be_empty
    expect(workout.reload.heart_rate_version).to eq(Allure::HeartRate::Histogram::VERSION)
  end

  it "never gives a credit row or a manual entry a histogram" do
    [ create(:workout, :credit, user:), create(:workout, :manual, user:) ].each do |other|
      described_class.new(workout: other).call

      expect(WorkoutHeartRate.where(workout: other)).to be_empty
      expect(other.reload.heart_rate_version).to eq(0)
    end
  end
end
