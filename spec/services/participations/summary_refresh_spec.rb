# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §6: a participation changes who the summary may name.
RSpec.describe Participations::SummaryRefresh, :assistant do
  include ActiveJob::TestHelper

  let(:user) { create(:user, ai_enabled: true) }
  let(:workout) { create(:workout, user:, analysis_version: 1, started_at: 2.days.ago) }
  let(:participant) { create(:user) }
  let(:participation) do
    create(:workout_participation, workout:,
                                   participant_actor: create(:actor, :local, user: participant))
  end

  it "schedules the source workout when a participation is confirmed" do
    expect { described_class.confirmed!(participation) }
      .to have_enqueued_job(Workouts::GenerateSummaryJob)

    expect(workout.reload.assistant_summary).to be_pending
  end

  it "drops a summary that names someone and schedules a new one on withdrawal" do
    create(:workout_summary, :ready, workout:,
                                     facts: [ { "id" => "company:with", "kind" => "company",
                                                "display" => "Avec Sophie", "weight" => 80 } ])

    expect { described_class.withdrawn!(participation) }
      .to have_enqueued_job(Workouts::GenerateSummaryJob)
      .and change { workout.reload.assistant_summary&.status }.from("ready").to("pending")
  end

  it "looks again at a summary that was being written when the confirmation landed" do
    create(:workout_summary, :pending, workout:)

    # `schedule` leaves a pending row alone, so the single job here is the
    # recheck that picks the new company fact up.
    expect { described_class.confirmed!(participation) }
      .to have_enqueued_job(Workouts::GenerateSummaryJob).exactly(:once)
    expect(workout.reload.assistant_summary).to be_pending
  end

  it "regenerates an old workout rather than keeping a name past the window" do
    old = create(:workout, user:, analysis_version: 1, started_at: 6.months.ago)
    old_participation = create(:workout_participation, workout: old,
                                                      participant_actor: create(:actor, :local, user: participant))
    create(:workout_summary, :ready, workout: old,
                                     facts: [ { "id" => "company:with", "kind" => "company",
                                                "display" => "Avec Sophie", "weight" => 80 } ])

    expect { described_class.withdrawn!(old_participation) }
      .to have_enqueued_job(Workouts::GenerateSummaryJob)
      .and change { old.reload.assistant_summary&.status }.from("ready").to("pending")
  end

  it "keeps a summary without a company fact, and still refreshes it" do
    summary = create(:workout_summary, :ready, workout:,
                                              facts: [ { "id" => "baseline:distance", "kind" => "baseline",
                                                         "display" => "62,4 km", "weight" => 100 } ])

    expect { described_class.withdrawn!(participation) }
      .to have_enqueued_job(Workouts::GenerateSummaryJob)
      .and change { workout.reload.assistant_summary&.status }.from("ready").to("pending")
    expect(summary.reload).to be_pending
  end
end
