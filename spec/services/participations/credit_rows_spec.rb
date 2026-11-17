# frozen_string_literal: true

require "rails_helper"

# docs/dev/SHARED-ACTIVITIES.md: the credit row lifecycle.
RSpec.describe Participations::CreditRows do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, username: "marie") }
  let(:participant) { create(:user, username: "paul") }
  let!(:owner_actor) { create(:local_actor, user: owner) }
  let(:participant_actor) { create(:local_actor, user: participant) }
  let(:sport) { catalog_sport("cycling") }
  let(:source) do
    create(:workout, user: owner, sport:, title: "Sortie du soir", distance: 42_000, moving_time: 5400,
                     duration: 6000, pause_time: 600, average_heart_rate: 150, calories: 900,
                     description: "Notes", source: "Garmin", commute: true)
  end

  def confirmed_credit(workout: source)
    create(:workout_participation, workout:, participant_actor:)
  end

  def credit_row_of(user = participant) = user.workouts.credit_rows_only.sole

  describe ".attach" do
    it "gives a confirmed credit a row with the credited metric set only" do
      row = described_class.attach(confirmed_credit)

      expect(row).to be_credit
      expect(row.user).to eq(participant)
      expect(row.credited_from).to eq(source)
      expect(row.credited_by).to eq(owner_actor)
      expect(row.attributes.slice("title", "distance", "moving_time", "sport_id", "started_at"))
        .to eq(source.attributes.slice("title", "distance", "moving_time", "sport_id", "started_at"))
      expect(row.attributes.values_at("average_heart_rate", "calories", "description", "source", "start_point"))
        .to all(be_nil)
      expect(row.commute).to be(false)
    end

    it "counts for the participant's records" do
      described_class.attach(confirmed_credit)

      record = Record.find_by(user: participant, sport:, record_type: "FD")
      expect(record.workout).to eq(credit_row_of)
      expect(record.value.to_f).to eq(42_000)
    end

    it "announces a new credit row once, to the participant's webhooks" do
      allow(Webhooks::Events).to receive(:workout_created)
      participation = confirmed_credit

      row = described_class.attach(participation)
      described_class.attach(participation)

      expect(Webhooks::Events).to have_received(:workout_created).with(row).once
    end

    it "is idempotent per source and participant" do
      participation = confirmed_credit

      first = described_class.attach(participation)
      expect { described_class.attach(participation) }.not_to change(Workout, :count)
      expect(described_class.attach(participation)).to eq(first)
    end

    it "does nothing for a link or a pending credit" do
      pending = create(:workout_participation, :pending, workout: source, participant_actor:)
      expect(described_class.attach(pending)).to be_nil

      link = create(:workout_participation, :link, workout: create(:workout, user: owner), participant_actor:)
      expect(described_class.attach(link)).to be_nil
      expect(participant.workouts.credit_rows_only).to be_empty
    end

    it "carries the source's biggest climb when the sport records elevation" do
      create(:detected_lap, workout: source, source: "climb", ascent: 310)
      create(:detected_lap, workout: source, source: "climb", ascent: 120)

      expect(described_class.attach(confirmed_credit).credited_max_climb.to_f).to eq(310)
    end

    it "re-attaches a detached row of the same owner instead of counting the outing twice" do
      described_class.attach(confirmed_credit)
      kept = credit_row_of
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!
      expect(kept.reload).to be_credit_detached

      reimported = create(:workout, user: owner, sport:, started_at: source.started_at + 30.seconds, title: "Re-import")
      row = described_class.attach(confirmed_credit(workout: reimported))

      expect(row).to eq(kept)
      expect(row.reload.credited_from).to eq(reimported)
      expect(row.credit_detached_at).to be_nil
      expect(row.title).to eq("Re-import")
      expect(participant.workouts.credit_rows_only.count).to eq(1)
    end
  end

  describe "confirmation" do
    it "enqueues the credit job, which creates the row" do
      participation = create(:workout_participation, :pending, workout: source, participant_actor:)

      perform_enqueued_jobs(only: Participations::CreditJob) do
        Participations::Decide.new(participation:, user: participant, decision: "confirm").call!
      end

      expect(credit_row_of.credited_from).to eq(source)
    end
  end

  describe "synchronization" do
    it "follows an edit of the source" do
      described_class.attach(confirmed_credit)

      perform_enqueued_jobs(only: Participations::CreditSyncJob) do
        source.update!(title: "Renamed", distance: 50_000)
      end

      expect(credit_row_of.title).to eq("Renamed")
      expect(credit_row_of.distance.to_f).to eq(50_000)
      expect(Record.find_by(user: participant, sport:, record_type: "FD").value.to_f).to eq(50_000)
    end

    it "ignores a change outside the column contract" do
      described_class.attach(confirmed_credit)

      expect { source.update!(notes: "Private") }.not_to have_enqueued_job(Participations::CreditSyncJob)
    end

    it "never writes a synced column through update_columns" do
      synced = Participations::CreditSync::SYNCED_COLUMNS.join("|")
      offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |line, index|
          next unless line.match?(/update_columns?\(/) && line.match?(/\b(#{synced})\b/)

          "#{Pathname(path).relative_path_from(Rails.root)}: #{line.strip}"
        end
      end

      # The loop segment's sport is not a workout column, and a remote credit's
      # detachment writes the credit row itself, which no credit row follows.
      expect(offenders).to contain_exactly(
        "app/jobs/segments/match_workout_job.rb: segment.update_columns(sport_id: nil)",
        "app/services/participations/remote_withdrawal.rb: credit.update_columns(credit_detached_at: at, title: nil, updated_at: at)"
      )
    end
  end

  describe "removal" do
    it "destroys the row on withdrawal and recomputes the participant's records" do
      participation = confirmed_credit
      described_class.attach(participation)

      Participations::Withdraw.new(participation:, user: owner).call!

      expect(participant.workouts.credit_rows_only).to be_empty
      expect(Record.where(user: participant)).to be_empty
    end

    it "destroys the row on conversion to a link" do
      participation = confirmed_credit
      described_class.attach(participation)
      recording = create(:workout, user: participant, started_at: source.started_at)

      Participations::Convert.new(participation:, user: participant, participant_workout: recording).call!

      expect(participant.workouts.credit_rows_only).to be_empty
      expect(participation.reload).to be_confirmed
    end

    it "withdraws the participation when the participant deletes the row, so it is never recreated" do
      participation = confirmed_credit
      described_class.attach(participation)

      Workouts::WorkoutDeletion.new(user: participant, workout: credit_row_of).call!

      expect(participation.reload).to be_withdrawn
      expect(described_class.attach(participation.reload)).to be_nil
      expect(participant.workouts.credit_rows_only).to be_empty
    end
  end

  describe "source deletion" do
    it "detaches and keeps the row, drops the owner's title, and tells the participant" do
      participation = confirmed_credit
      described_class.attach(participation)
      row = credit_row_of

      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!

      row.reload
      expect(row).to be_credit_detached
      expect(row.credit_detached_at).to be_present
      expect(row.title).to be_nil
      expect(row.distance.to_f).to eq(42_000)
      expect(row.credited_by).to eq(owner_actor)
      expect(Record.find_by(user: participant, sport:, record_type: "FD").workout).to eq(row)
      expect(WorkoutParticipation.exists?(participation.id)).to be(false)
      notice = Notification.find_by(user: participant, kind: "participation_source_deleted")
      expect(notice.subject).to eq(row)
      expect(notice.actor).to be_nil
    end

    it "never syncs a detached row" do
      described_class.attach(confirmed_credit)
      row = credit_row_of
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!

      expect { Participations::CreditSync.new(row.reload).call }.not_to(change { row.reload.attributes })
    end

    it "detaches through the owner's account deletion too" do
      described_class.attach(confirmed_credit)
      row = credit_row_of

      Users::DeleteAccount.new(user: owner).call!

      expect(row.reload).to be_credit_detached
      expect(row.credited_by).to be_tombstoned
      expect(Notification.where(user: participant, kind: "participation_source_deleted")).to exist
    end

    it "withdraws the notice when the participant later deletes the kept row" do
      described_class.attach(confirmed_credit)
      row = credit_row_of
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!

      Workouts::WorkoutDeletion.new(user: participant, workout: row.reload).call!

      expect(Notification.where(user: participant, kind: "participation_source_deleted")).to be_empty
    end
  end
end
