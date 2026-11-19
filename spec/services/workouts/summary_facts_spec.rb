# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §3.1: the facts of one workout, assembled from the owner's
# stored history. The detectors themselves are pure (facts_spec); this proves
# the ContextPayload wiring reaches them.
RSpec.describe Workouts::SummaryFacts do
  def ride(started_at:, distance: 55_000.0, speed: 6.5, ascent: 100.0, moving: 8_500)
    create(:workout, user:, sport:, started_at:, distance:, average_speed: speed, ascent:,
                     duration: moving, moving_time: moving, pause_time: 0)
  end

  let(:user) { create(:user) }
  let(:sport) { catalog_sport("cycling") }
  let(:workout) do
    create(:workout, user:, sport:, started_at: Time.zone.parse("2026-11-17 09:00:00"),
                     distance: 60_000.0, average_speed: 7.5, ascent: 120.0,
                     duration: 8_000, moving_time: 8_000, pause_time: 0)
  end

  before do
    4.times do |index|
      ride(started_at: Time.zone.parse("2026-10-01 09:00:00") - index.days)
    end
  end

  it "builds the history facts from the owner's year" do
    facts = described_class.new(workout).call.facts

    expect(facts.find { it.id == "history:pace" }).to have_attributes(sentiment: :good)
    expect(facts.find { it.id == "history:gap" }).to be_present
    expect(facts.find { it.id == "history:similar" }).to be_present
  end

  it "omits the history facts when the sport has no earlier outing" do
    other = create(:workout, user:, sport: catalog_sport("running"),
                             started_at: Time.zone.parse("2026-11-17 09:00:00"))

    expect(described_class.new(other).call.facts.select { it.kind == "history" }).to be_empty
  end

  it "keeps a stable digest for unchanged facts" do
    first = described_class.new(workout).call
    second = described_class.new(workout).call

    expect(second.digest).to eq(first.digest)
  end

  it "carries the sport's slug for the prompt's jargon" do
    expect(described_class.new(workout).call.sport_slug).to eq("cycling")
  end

  it "cuts the recorded route around the detected climb" do
    climb = create(:workout, user:, sport:, started_at: Time.zone.parse("2026-11-17 09:00:00"),
                             distance: 4_000.0, average_speed: 2.5, ascent: 80.0,
                             duration: 1_600, moving_time: 1_600, pause_time: 0)
    points = [ [ 0, 0, 100 ], [ 1_000, 400, 104 ], [ 2_000, 800, 108 ],
               [ 3_000, 1_200, 144 ], [ 4_000, 1_600, 180 ] ].map do |distance, seconds, elevation|
      { "t" => seconds, "d" => distance, "lat" => 45.0 + (distance * 0.000009), "lon" => 6.0, "ele" => elevation }
    end
    create(:track_segment, workout: climb, points:, distance: 4_000.0)
    create(:detected_lap, :climb, :named, workout: climb, number: 1, start_distance: 2_000.0,
                                          end_distance: 4_000.0, distance: 2_000.0, ascent: 72.0,
                                          name: "Le refuge")

    snapshot = described_class.new(climb).call

    expect(snapshot.course.mode).to eq(:terrain)
    expect(snapshot.course.sections.map { it.ascent.round }).to eq([ 8, 72 ])
    expect(snapshot.facts.find { it.id == "section:2" }.display).to include("montée « Le refuge »")
  end

  it "falls back to equal parts when no climb was detected" do
    loop_ride = create(:workout, user:, sport:, started_at: Time.zone.parse("2026-11-18 09:00:00"),
                                 distance: 10_000.0, average_speed: 6.0, ascent: 0.0,
                                 duration: 1_700, moving_time: 1_700, pause_time: 0)
    points = 0.upto(10).map do |index|
      { "t" => index * 170, "d" => index * 1_000, "lat" => 45.0 + (index * 0.00009), "lon" => 6.0 }
    end
    create(:track_segment, workout: loop_ride, points:, distance: 10_000.0)

    snapshot = described_class.new(loop_ride).call

    expect(snapshot.course.mode).to eq(:parts)
    expect(snapshot.course.sections.length).to eq(4)
    expect(snapshot.facts.select { it.kind == "section" }.length).to eq(4)
  end

  it "writes no course for a workout too short to have sections" do
    short = create(:workout, user:, sport:, started_at: Time.zone.parse("2026-11-17 09:00:00"),
                             distance: 2_000.0, duration: 900, moving_time: 900, pause_time: 0)
    points = 0.upto(4).map { |index| { "t" => index * 200, "d" => index * 500, "lat" => 45.0, "lon" => 6.0 } }
    create(:track_segment, workout: short, points:, distance: 2_000.0)

    expect(described_class.new(short).call.course).to be_nil
  end
end
