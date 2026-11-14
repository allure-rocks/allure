# frozen_string_literal: true

require "rails_helper"

# PLAN_TOGETHER.md §6.6: the sweeps that assume a track never pick a credit
# row, the participant's own recording of a credited outing is still
# imported, and the instance counts an outing once.
RSpec.describe "Credit row exclusions" do
  let(:sport) { catalog_sport("cycling") }
  let(:participant) { create(:user, elevation_enrichment_enabled: true) }
  let!(:credit) do
    create(:workout, :credit, user: participant, sport:, route_image_version: 0, recorded_elevation: false)
  end

  it "keeps credit rows out of the route image, elevation and toponymy sweeps" do
    expect(Workouts::BackfillRouteImagesJob.pending_scope).not_to include(credit)
    expect(Workouts::BackfillElevationJob.pending_scope).not_to include(credit)
    expect(Workouts::BackfillToponymyJob.pending_scope).not_to include(credit)
  end

  it "counts nothing to repair for an account holding only a credit row" do
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)

    counts = Workouts::UserBackfillJob.counts(participant)

    expect(counts.values_at("route_images", "places", "elevation")).to all(eq(0))
  end

  it "still imports the participant's own recording of a credited outing" do
    job = Workouts::RemoteImportBatchJob.new

    expect(job.send(:near_duplicate, participant, credit.started_at + 30.seconds)).to be_nil
  end

  it "counts an outing once in the instance figures" do
    snapshot = Metrics::Snapshot.new.call.domain
    overview = Admin::Dashboard::Overview.new.call

    expect(snapshot[:workouts]).to eq(Workout.recordings.count)
    expect(snapshot[:workouts_distance_meters]).to eq(Workout.recordings.sum(:distance).to_f)
    expect(overview.workouts[:total]).to eq(Workout.recordings.count)
  end
end
