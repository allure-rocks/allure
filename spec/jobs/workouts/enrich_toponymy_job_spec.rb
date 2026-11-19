# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::EnrichToponymyJob do
  it "enriches the workout idempotently" do
    workout = create(:workout)
    service = instance_double(Workouts::ToponymyEnricher, call: true)
    allow(Workouts::ToponymyEnricher).to receive(:new).with(workout:).and_return(service)

    described_class.perform_now(workout)

    expect(service).to have_received(:call).with(no_args)
  end

  it "reschedules the assistant summary once the places are known" do
    workout = create(:workout)
    allow(Workouts::ToponymyEnricher).to receive(:new).and_return(instance_double(Workouts::ToponymyEnricher, call: true))
    allow(Workouts::SummaryRefresh).to receive(:schedule)

    described_class.perform_now(workout)

    expect(Workouts::SummaryRefresh).to have_received(:schedule).with(workout)
  end

  it "never replays the geocoding for a summary failure" do
    workout = create(:workout)
    enricher = instance_double(Workouts::ToponymyEnricher, call: true)
    allow(Workouts::ToponymyEnricher).to receive(:new).and_return(enricher)
    allow(Workouts::SummaryRefresh).to receive(:schedule).and_raise(StandardError, "boom")
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now(workout) }.not_to raise_error

    expect(enricher).to have_received(:call).once
    expect(Rails.error).to have_received(:report).with(an_instance_of(StandardError), hash_including(handled: true))
  end
end
