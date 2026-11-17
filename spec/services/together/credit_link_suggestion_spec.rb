# frozen_string_literal: true

require "rails_helper"

# docs/dev/SHARED-ACTIVITIES.md: a credited participant's own recording of the same
# outing is suggested as a link, through the detector, never by start time.
RSpec.describe Together::CreditLinkSuggestion do
  include ActiveJob::TestHelper

  let(:sport) { catalog_sport("cycling") }
  let(:marie) { create(:user, username: "marie") }
  let(:paul) { create(:user, username: "paul") }
  let!(:marie_actor) { create(:local_actor, user: marie) }
  let!(:paul_actor) { create(:local_actor, user: paul) }
  let(:source) { recording(marie, title: "Sortie de Marie") }
  let!(:participation) { create(:workout_participation, workout: source, participant_actor: paul_actor) }

  def recording(user, **attributes)
    workout = create(:workout, user:, sport:, **attributes)
    create(:track_segment, workout:)
    workout
  end

  it "suggests the participant's co-present recording once imported, and tells them" do
    own = recording(paul)

    Together::Detection.call(own)

    expect(participation.reload.suggested_workout).to eq(own)
    expect(participation).to be_link_suggestion_open
    notice = Notification.find_by!(user: paul, kind: "participation_link_suggested")
    expect(notice.subject).to eq(participation)
    expect(notice.actor).to be_nil
  end

  it "suggests at confirmation when the recording already exists" do
    own = recording(paul)
    pending = create(:workout_participation, :pending, workout: recording(marie), participant_actor: paul_actor)

    perform_enqueued_jobs(only: Participations::CreditJob) do
      Participations::Decide.new(participation: pending, user: paul, decision: "confirm").call!
    end

    expect(pending.reload.suggested_workout).to eq(own)
  end

  it "never suggests a recording of another time, nor for an opted-out participant" do
    later = recording(paul, started_at: source.started_at + 3.hours)
    later.track_segments.update_all(started_at: later.started_at)
    Together::Detection.call(later)
    expect(participation.reload.suggested_workout).to be_nil

    paul.update!(together_detection_enabled: false)
    Together::Detection.call(recording(paul))
    expect(participation.reload.suggested_workout).to be_nil
  end

  it "keeps a dismissal for good" do
    Together::Detection.call(recording(paul))
    participation.reload.update!(suggested_workout: nil, link_suggestion_dismissed_at: Time.current)

    Together::Detection.call(recording(paul))

    expect(participation.reload.suggested_workout).to be_nil
  end

  it "clears the suggestion and its notice when the credit converts" do
    own = recording(paul)
    Together::Detection.call(own)

    Participations::Convert.new(participation: participation.reload, user: paul, participant_workout: own).call!

    expect(participation.reload).to have_attributes(kind: "link", participant_workout: own, suggested_workout: nil)
    expect(Notification.where(kind: "participation_link_suggested")).to be_empty
  end
end
