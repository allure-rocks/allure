# frozen_string_literal: true

require "rails_helper"

# docs/dev/SHARED-ACTIVITIES.md: a credit row's best efforts and segment efforts
# are derived from its source's points for the participant, kinematics only,
# off shared boards and counters, and frozen once the source is deleted.
RSpec.describe "Credit row derivations" do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, username: "marie") }
  let(:participant) { create(:user, username: "paul") }
  let!(:owner_actor) { create(:local_actor, user: owner) }
  let(:participant_actor) { create(:local_actor, user: participant) }
  let(:sport) { create(:sport) }
  let(:source) { create(:workout, user: owner, sport:) }

  before do
    allow(Segments::BackfillSegmentJob).to receive(:perform_later)
    create(:track_segment, workout: source, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0, "hr" => 140, "pw" => 200 },
      { "t" => 60, "d" => 250.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0, "hr" => 150, "pw" => 210 }
    ])
  end

  def credit!
    participation = create(:workout_participation, workout: source, participant_actor:)
    Participations::CreditRows.attach(participation)
  end

  describe "segment efforts" do
    let!(:segment) { create(:segment, user: owner, sport:, visibility: "public") }

    it "matches the credit row for the participant on the source's points, kinematics only" do
      Segments::MatchWorkoutJob.perform_now(source)
      credit = credit!
      Segments::MatchWorkoutJob.perform_now(credit)

      effort = SegmentEffort.find_by!(segment:, workout: credit)
      expect(effort).to have_attributes(user: participant, elapsed_time: 60, personal_best: true)
      expect(effort.attributes.values_at("average_heart_rate", "max_heart_rate", "average_power", "max_power"))
        .to all(be_nil)
      expect(SegmentEffort.find_by!(segment:, workout: source).average_heart_rate).to be_present
    end

    it "keeps credited efforts out of the counters and off the shared board" do
      Segments::MatchWorkoutJob.perform_now(source)
      Segments::MatchWorkoutJob.perform_now(credit!)

      expect(segment.reload).to have_attributes(efforts_count: 1, athletes_count: 1)
      expect(segment.participants_count).to eq(1)
      expect(Segments::Listing.for_segment(segment, viewer: create(:user)).map(&:user_id)).not_to include(participant.id)
      expect(Segments::Reach.new(segment:, user: participant).call).to eq("credited")
    end

    it "is enqueued by the credit sync" do
      expect { credit! }.to have_enqueued_job(Segments::MatchWorkoutJob)
    end

    it "matches the participant's private segments, never the owner's, nor routes or loops" do
      private_segment = create(:segment, user: participant, sport:)
      owner_private = create(:segment, user: owner, sport:)
      participant_route = create(:segment, :route, user: participant, sport:)
      credit = credit!

      Segments::MatchWorkoutJob.perform_now(credit)

      expect(credit.segment_efforts.pluck(:segment_id))
        .to contain_exactly(segment.id, private_segment.id)
      expect(credit.segment_efforts.where(segment_id: [ owner_private.id, participant_route.id ])).to be_empty
      expect(Segments::CandidateQuery.for_segment(private_segment)).to include(credit)
      expect(Segments::CandidateQuery.for_segment(participant_route)).not_to include(credit)
    end

    it "freezes the efforts once the source is deleted" do
      credit = credit!
      Segments::MatchWorkoutJob.perform_now(credit)
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!
      credit.reload

      expect { Segments::MatchWorkoutJob.perform_now(credit) }.not_to(change { credit.segment_efforts.count })
      expect(credit.segment_efforts.count).to eq(1)
      expect(Segments::CandidateQuery.for_segment(segment)).not_to include(credit)
    end

    it "keeps frozen efforts through a tolerance change and drops them with the segment's activity" do
      credit = credit!
      Segments::MatchWorkoutJob.perform_now(credit)
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!

      Segments::Updater.new(segment:, attributes: { "match_tolerance_meters" => "30" }).call
      expect(credit.segment_efforts.count).to eq(1)

      Segments::Updater.new(segment:, attributes: { "active" => "false" }).call
      expect(credit.segment_efforts.count).to eq(0)
    end
  end

  describe "best efforts" do
    let(:sport) { catalog_sport("running") }
    let(:source) { create(:workout, user: owner, sport:, distance: 5_000.0) }

    before do
      source.track_segments.delete_all
      points = (0..50).map do |index|
        { "t" => index * 10, "d" => index * 100.0, "lat" => 45.0 + (index * 100 / 111_320.0), "lon" => 6.0, "ele" => 100.0 }
      end
      create(:track_segment, workout: source, distance: 5_000.0, points:)
      BestEfforts::Rebuild.new(workout: source).call
    end

    it "rebuilds the source's efforts on the credit row for the participant" do
      credit = credit!

      five = credit.best_efforts.find_by!(distance_key: "km5")
      expect(five).to have_attributes(user_id: participant.id, duration_seconds: 500)
      expect(source.best_efforts.where(user: owner).count).to eq(source.best_efforts.count)
      expect(EffortRecord.find_by!(user: participant, distance_key: "km5").workout).to eq(credit)
    end

    it "keeps frozen efforts on a detached row through a rebuild and the sweep" do
      credit = credit!
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!

      BestEfforts::Rebuild.new(workout: credit.reload).call
      BestEfforts::BackfillJob.perform_now

      expect(credit.best_efforts.find_by(distance_key: "km5")).to be_present
    end

    it "is rebuilt from the source by the backfill sweep" do
      credit = credit!
      credit.best_efforts.delete_all

      BestEfforts::BackfillJob.perform_now

      expect(credit.best_efforts.find_by(distance_key: "km5")).to be_present
    end
  end

  describe "biggest climb record" do
    let(:sport) { catalog_sport("cycling") }

    it "takes the credited climb when it is the largest, and keeps it after detachment" do
      create(:detected_lap, workout: source, source: "climb", ascent: 400)
      own = create(:workout, user: participant, sport:)
      create(:detected_lap, workout: own, source: "climb", ascent: 250)
      credit = credit!

      record = Record.find_by!(user: participant, sport:, record_type: "MC")
      expect(record.workout).to eq(credit)
      expect(record.value.to_f).to eq(400)

      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!
      Records::RecomputeService.new(user: participant, sport:).call
      expect(Record.find_by!(user: participant, sport:, record_type: "MC").workout).to eq(credit)
    end

    it "keeps the participant's own climb when it is larger" do
      create(:detected_lap, workout: source, source: "climb", ascent: 100)
      own = create(:workout, user: participant, sport:)
      create(:detected_lap, workout: own, source: "climb", ascent: 250)
      credit!

      expect(Record.find_by!(user: participant, sport:, record_type: "MC").workout).to eq(own)
    end
  end
end
