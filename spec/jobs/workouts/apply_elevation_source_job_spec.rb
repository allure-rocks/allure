# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ApplyElevationSourceJob do
  let(:workout) { create(:workout) }

  def stub_enricher(status)
    result = Workouts::ElevationEnricher::Result.new(status:, samples_count: 3, requests_count: 1)
    enricher = instance_double(Workouts::ElevationEnricher, call: result)
    allow(Workouts::ElevationEnricher).to receive(:new).with(workout:).and_return(enricher)
  end

  it "ensures the cache and enqueues the forced reanalysis for dem" do
    create(:workout_elevation, workout:, status: "ready")
    stub_enricher("ready")

    expect(Workouts::ReanalyzeJob).to receive(:perform_later).with(workout, "dem")

    described_class.perform_now(workout, "dem")
  end

  it "does not reanalyze when the provider yields nothing usable" do
    create(:workout_elevation, workout:, status: "unavailable")
    stub_enricher("unavailable")

    expect(Workouts::ReanalyzeJob).not_to receive(:perform_later)

    described_class.perform_now(workout, "dem")
  end

  it "clears a pending request when the provider yields nothing usable" do
    workout.update!(elevation_source_requested: "dem")
    create(:workout_elevation, workout:, status: "unavailable")
    stub_enricher("unavailable")

    described_class.perform_now(workout, "dem")

    expect(workout.reload.elevation_source_requested).to be_nil
  end

  it "clears a pending request when the job is discarded" do
    workout.update!(elevation_source_requested: "dem")
    enricher = instance_double(Workouts::ElevationEnricher)
    allow(Workouts::ElevationEnricher).to receive(:new).with(workout:).and_return(enricher)
    allow(enricher).to receive(:call).and_raise(Workouts::ElevationEnricher::ProviderNotConfiguredError)

    described_class.perform_now(workout, "dem")

    expect(workout.reload.elevation_source_requested).to be_nil
  end

  it "geocodes a deferred import on its recorded profile when the terrain never comes" do
    workout.update!(elevation_source_requested: "dem")
    create(:workout_toponymy, workout:, status: "pending")
    create(:workout_elevation, workout:, status: "unavailable")
    stub_enricher("unavailable")

    expect(Workouts::EnrichToponymyJob).to receive(:perform_later).with(workout)

    described_class.perform_now(workout, "dem")
  end

  it "leaves settled places alone when an owner's terrain request fails" do
    workout.update!(elevation_source_requested: "dem")
    create(:workout_toponymy, workout:)
    create(:workout_elevation, workout:, status: "unavailable")
    stub_enricher("unavailable")

    expect(Workouts::EnrichToponymyJob).not_to receive(:perform_later)

    described_class.perform_now(workout, "dem")
  end

  it "applies the recorded profile without contacting the provider" do
    expect(Workouts::ElevationEnricher).not_to receive(:new)
    expect(Workouts::ReanalyzeJob).to receive(:perform_later).with(workout, "device")

    described_class.perform_now(workout, "device")
  end

  it "ignores an unknown source" do
    expect(Workouts::ElevationEnricher).not_to receive(:new)
    expect(Workouts::ReanalyzeJob).not_to receive(:perform_later)

    described_class.perform_now(workout, "gps")
  end
end
