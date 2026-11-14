# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::RouteSuggestionDetector do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def recording(started_at: Time.zone.parse("2026-08-23 06:00:00"), points: route_suggestion_track,
                workout_user: user, workout_sport: sport)
    route_suggestion_recording(user: workout_user, sport: workout_sport, started_at:, points:)
  end

  # The same track, shifted north by `metres`: the shape and length are
  # unchanged, only the endpoints drift, which is what the route tolerance
  # absorbs.
  def shifted_track(metres)
    route_suggestion_track.map do |point|
      point.merge("lat" => point.fetch("lat") + (metres / 111_320.0))
    end
  end

  it "suggests a route after three recordings of the same complete track" do
    oldest = recording(started_at: 3.days.ago)
    middle = recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)

    suggestion = described_class.call(newest)

    expect(suggestion).to be_pending
    expect(suggestion.reference_workout).to eq(newest)
    expect(suggestion.workouts).to contain_exactly(oldest, middle, newest)
    expect(newest.reload.route_suggestion_version).to eq(described_class::VERSION)
  end

  it "does not suggest a route after two recordings" do
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)

    expect(described_class.call(newest)).to be_nil
    expect(RouteSuggestion.count).to eq(0)
    expect(newest.reload.route_suggestion_version).to eq(described_class::VERSION)
  end

  it "refuses a reversed complete track" do
    recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    reversed = recording(started_at: 1.day.ago, points: route_suggestion_track.reverse)

    expect(described_class.call(reversed)).to be_nil
  end

  it "keeps sports apart" do
    other_sport = create(:sport)
    recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago, workout_sport: other_sport)

    expect(described_class.call(newest)).to be_nil
  end

  it "never compares another account's recordings" do
    other = create(:user)
    recording(started_at: 3.days.ago, workout_user: other)
    recording(started_at: 2.days.ago, workout_user: other)
    newest = recording(started_at: 1.day.ago)

    expect(described_class.call(newest)).to be_nil
  end

  it "does nothing for a recording already covered by a route" do
    oldest = recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)
    Segments::Creator.new(user:, workout: oldest, kind: "route", name: "Commute").call

    expect(described_class.call(newest)).to be_nil
  end

  it "accepts a recording whose endpoints drift by the route tolerance" do
    recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago, points: shifted_track(60))

    suggestion = described_class.call(newest)

    expect(suggestion).to be_pending
    expect(suggestion.workouts.count).to eq(3)
  end

  it "keeps a parallel route beyond the tolerance apart" do
    recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    parallel = recording(started_at: 1.day.ago, points: shifted_track(150))

    expect(described_class.call(parallel)).to be_nil
  end

  it "does not suggest a recording that resembles an existing route at the route tolerance" do
    oldest = recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago, points: shifted_track(60))
    Segments::Creator.new(
      user:, workout: oldest, kind: "route", name: "Commute", match_tolerance_meters: 25
    ).call

    expect(described_class.call(newest)).to be_nil
  end

  it "joins a later recording to the pending suggestion" do
    oldest = recording(started_at: 3.days.ago)
    middle = recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)
    suggestion = described_class.call(newest)
    later = recording(started_at: Time.current)

    expect(described_class.call(later)).to eq(suggestion)
    expect(suggestion.reload.workouts).to contain_exactly(oldest, middle, newest, later)
  end

  it "keeps a dismissed suggestion dismissed while absorbing the repeat" do
    recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)
    suggestion = described_class.call(newest)
    suggestion.update!(status: "dismissed")
    later = recording(started_at: Time.current)

    expect(described_class.call(later)).to eq(suggestion)
    expect(suggestion.reload).to be_dismissed
    expect(suggestion.workouts).to include(later)
  end

  it "is idempotent" do
    recording(started_at: 3.days.ago)
    recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)

    first = described_class.call(newest)
    second = described_class.call(newest)

    expect(second).to be_nil
    expect(RouteSuggestion.count).to eq(1)
    expect(RouteSuggestionWorkout.count).to eq(3)
    expect(first.reload.workouts.count).to eq(3)
  end

  it "does not suggest for a positionless recording" do
    newest = create(:workout, :unpositioned, user:, sport:)

    expect(described_class.call(newest)).to be_nil
  end

  it "ignores a suggestion whose reference has no track" do
    reference = create(:workout, user:, sport:)
    suggestion = create(:route_suggestion, user:, sport:, reference_workout: reference)
    create(:route_suggestion_workout, route_suggestion: suggestion, workout: reference)
    newest = recording(started_at: 1.day.ago)

    expect(described_class.call(newest)).to be_nil
  end
end
