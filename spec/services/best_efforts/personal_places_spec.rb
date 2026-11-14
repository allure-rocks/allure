# frozen_string_literal: true

require "rails_helper"

RSpec.describe BestEfforts::PersonalPlaces do
  let(:user) { create(:user) }
  let(:running) { catalog_sport("running") }
  let(:cycling) { catalog_sport("cycling") }

  def effort(duration, started_at:, sport: running, distance_key: "km5", owner: user)
    workout = create(:workout, user: owner, sport:, started_at:)
    create(:best_effort, workout:, distance_key:, duration_seconds: duration, started_at:)
  end

  it "places each effort among the athlete's own efforts over the same sport and distance" do
    fourth = effort(1_400, started_at: 5.days.ago)
    record = effort(1_100, started_at: 4.days.ago)
    third = effort(1_300, started_at: 3.days.ago)
    second = effort(1_200, started_at: 2.days.ago)

    places = described_class.new(user:, best_efforts: [ record, second, third, fourth ]).call

    expect(places).to eq(record.id => 1, second.id => 2, third.id => 3)
  end

  it "breaks ties on the earlier start, like the effort record" do
    later = effort(1_200, started_at: 1.day.ago)
    earlier = effort(1_200, started_at: 3.days.ago)

    expect(described_class.new(user:, best_efforts: [ later, earlier ]).call).to eq(earlier.id => 1, later.id => 2)
  end

  it "ranks each sport, each distance and each athlete separately" do
    mine = effort(1_500, started_at: 4.days.ago)
    effort(1_000, started_at: 3.days.ago, sport: cycling)
    effort(1_000, started_at: 3.days.ago, distance_key: "km10")
    effort(1_000, started_at: 3.days.ago, owner: create(:user))

    expect(described_class.new(user:, best_efforts: [ mine ]).call).to eq(mine.id => 1)
  end

  it "agrees with the recomputed effort record on the gold place" do
    effort(1_300, started_at: 3.days.ago)
    best = effort(1_100, started_at: 2.days.ago)
    Records::RecomputeService.new(user:, sport: running).call

    record = EffortRecord.find_by!(user:, sport: running, distance_key: "km5")
    expect(described_class.new(user:, best_efforts: [ best ]).call[best.id]).to eq(1)
    expect(record.workout_id).to eq(best.workout_id)
  end

  it "answers nothing without efforts" do
    expect(described_class.new(user:, best_efforts: []).call).to eq({})
  end
end
