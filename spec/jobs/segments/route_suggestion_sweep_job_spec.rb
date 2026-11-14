# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::RouteSuggestionSweepJob do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  it "walks the account newest first and anchors the suggestion on the newest recording" do
    oldest = route_suggestion_recording(user:, sport:, started_at: 3.days.ago)
    middle = route_suggestion_recording(user:, sport:, started_at: 2.days.ago)
    newest = route_suggestion_recording(user:, sport:, started_at: 1.day.ago)

    described_class.perform_now(user.id)

    suggestion = RouteSuggestion.find_by!(user:)
    expect(suggestion.reference_workout).to eq(newest)
    expect(suggestion.workouts).to contain_exactly(oldest, middle, newest)
    expect([ oldest, middle, newest ].map { |workout| workout.reload.route_suggestion_version })
      .to all(eq(Segments::RouteSuggestionDetector::VERSION))
  end

  it "resumes after the cursor" do
    newest = route_suggestion_recording(user:, sport:, started_at: 1.day.ago)
    middle = route_suggestion_recording(user:, sport:, started_at: 2.days.ago)
    oldest = route_suggestion_recording(user:, sport:, started_at: 3.days.ago)

    described_class.perform_now(user.id, cursor_started_at: middle.started_at.iso8601, cursor_id: middle.id)

    expect(newest.reload.route_suggestion_version).to eq(0)
    expect(middle.reload.route_suggestion_version).to eq(0)
    expect(oldest.reload.route_suggestion_version).to eq(Segments::RouteSuggestionDetector::VERSION)
  end

  it "does nothing for a deactivated account" do
    user.update!(suspended_at: Time.current)
    workout = route_suggestion_recording(user:, sport:)

    described_class.perform_now(user.id)

    expect(workout.reload.route_suggestion_version).to eq(0)
  end

  it "counts the recordings the detector has not examined" do
    route_suggestion_recording(user:, sport:)
    examined = route_suggestion_recording(user:, sport:, started_at: 1.day.ago)
    examined.update_columns(route_suggestion_version: Segments::RouteSuggestionDetector::VERSION)

    expect(described_class.pending_scope.count).to eq(1)
  end

  it "enqueues one sweep per concerned account" do
    route_suggestion_recording(user:, sport:)
    other = create(:user)
    route_suggestion_recording(user: other, sport:)

    expect { described_class.enqueue_all }
      .to have_enqueued_job(described_class).with(user.id)
      .and have_enqueued_job(described_class).with(other.id)
  end
end
