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
end
