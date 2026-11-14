# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::RebuildPlacesJob do
  it "reassembles the workout places" do
    workout = create(:workout)
    namer = instance_double(Workouts::PlaceNamer, call: [])
    allow(Workouts::PlaceNamer).to receive(:new).with(workout:).and_return(namer)

    described_class.perform_now(workout)

    expect(namer).to have_received(:call)
  end
end
