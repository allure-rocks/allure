# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::VirtualVenueNamer do
  let(:user) { create(:user) }
  # The reference catalogs are seeded in the test database (db:prepare seeds a
  # fresh one, as CI does), so catalog slugs go through the find-or-create
  # helper rather than the factory.
  let(:rowing_virtual) { catalog_sport("rowing_virtual") }
  let(:workout) do
    create(
      :workout,
      user:,
      sport: rowing_virtual,
      source: "EXR",
      start_point: geographic_point(-0.885, 51.545)
    )
  end

  it "names the world whose radius contains the start point" do
    places = described_class.new(workout:).call

    expect(places).to eq([ { "name" => "Henley", "kind" => "virtual_venue" } ])
    expect(workout.reload.places).to eq(places)
    expect(workout.place_names.order(:position).pluck(:name, :kind)).to eq([ [ "Henley", "virtual_venue" ] ])
  end

  it "leaves both lists empty when the world is unknown" do
    workout.update_columns(start_point: geographic_point(2.3522, 48.8566))

    described_class.new(workout:).call

    expect(workout.reload.places).to eq([])
    expect(workout.place_names).to be_empty
  end

  it "clears a stale list when the workout is re-located" do
    workout.update_columns(places: [ { "name" => "Honfleur", "kind" => "town" } ])
    create(:workout_place_name, workout:, user:, name: "Honfleur", kind: "town")

    described_class.new(workout:).call

    expect(workout.reload.places).to eq([ { "name" => "Henley", "kind" => "virtual_venue" } ])
    expect(workout.place_names.order(:position).pluck(:name)).to eq([ "Henley" ])
  end

  it "never touches a workout whose sport is not virtual" do
    rowing = catalog_sport("rowing")
    workout = create(
      :workout,
      user:,
      sport: rowing,
      source: "EXR",
      start_point: geographic_point(-0.885, 51.545)
    )
    workout.update_columns(places: [ { "name" => "Mlino", "kind" => "hamlet" } ])

    described_class.new(workout:).call

    expect(workout.reload.places).to eq([ { "name" => "Mlino", "kind" => "hamlet" } ])
  end

  it "has no world to name without a platform creator" do
    workout.update_columns(source: nil)

    described_class.new(workout:).call

    expect(workout.reload.places).to eq([])
  end
end
