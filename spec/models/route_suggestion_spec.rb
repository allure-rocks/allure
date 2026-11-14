# frozen_string_literal: true

require "rails_helper"

RSpec.describe RouteSuggestion do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def recording(started_at:)
    route_suggestion_recording(user:, sport:, started_at:)
  end

  it "falls back to the newest remaining member when the reference is deleted" do
    oldest = recording(started_at: 3.days.ago)
    middle = recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)
    suggestion = Segments::RouteSuggestionDetector.call(newest)

    newest.destroy!

    expect(suggestion.reload.reference_workout).to be_nil
    expect(suggestion.effective_reference_workout).to eq(middle)
    expect(suggestion.workouts).to contain_exactly(oldest, middle)
  end

  it "disappears when its last member is deleted" do
    oldest = recording(started_at: 3.days.ago)
    middle = recording(started_at: 2.days.ago)
    newest = recording(started_at: 1.day.ago)
    suggestion = Segments::RouteSuggestionDetector.call(newest)

    [ oldest, middle, newest ].each(&:destroy!)

    expect(RouteSuggestion.exists?(suggestion.id)).to be(false)
  end

  it "refuses a segment that is not a route" do
    suggestion = build(:route_suggestion, user:, sport:, reference_workout: recording(started_at: 1.day.ago))
    suggestion.segment = create(:segment, user:, sport:)

    expect(suggestion).not_to be_valid
    expect(suggestion.errors[:segment]).to be_present
  end

  it "refuses another account's reference workout" do
    suggestion = build(:route_suggestion, user:, sport:, reference_workout: create(:workout))

    expect(suggestion).not_to be_valid
    expect(suggestion.errors[:reference_workout]).to be_present
  end
end
