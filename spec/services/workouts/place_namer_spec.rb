# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PlaceNamer do
  let(:workout) { create(:workout, distance: 10_000.0) }

  def toponymy(attrs = {})
    create(:workout_toponymy, workout:, **attrs)
  end

  let(:endpoints) do
    { start_place: { "name" => "Valmorin", "kind" => "village" },
      finish_place: { "name" => "Rochelune", "kind" => "city" } }
  end

  it "keeps the best-ranked marker and the arrival, in route order" do
    record = toponymy(
      **endpoints,
      markers: [
        { "distance" => 5_000.0, "name" => "Best", "kind" => "town", "rank" => 1 },
        { "distance" => 2_000.0, "name" => "Second", "kind" => "village", "rank" => 2 }
      ]
    )

    described_class.new(workout:).call

    expect(record.reload.places).to eq([
      { "name" => "Valmorin", "kind" => "village" },
      { "name" => "Best", "kind" => "town" },
      { "name" => "Rochelune", "kind" => "city" }
    ])
    expect(record.places_algorithm_version).to eq(described_class::ALGORITHM_VERSION)
    expect(workout.reload.places).to eq(record.places)
  end

  it "indexes every recorded place beyond the displayed three" do
    record = toponymy(
      **endpoints,
      markers: [
        { "distance" => 1_000.0, "name" => "A", "kind" => "hamlet", "rank" => 1 },
        { "distance" => 2_000.0, "name" => "B", "kind" => "hamlet", "rank" => 2 },
        { "distance" => 3_000.0, "name" => "C", "kind" => "hamlet", "rank" => 3 },
        { "distance" => 4_000.0, "name" => "D", "kind" => "hamlet", "rank" => 4 }
      ]
    )

    described_class.new(workout:).call

    expect(record.reload.places.pluck("name")).to eq(%w[Valmorin A Rochelune])
    expect(workout.place_names.order(:position).pluck(:name)).to eq(%w[Valmorin A B C D Rochelune])
    expect(workout.place_names.order(:position).pluck(:position)).to eq((0..5).to_a)
    expect(workout.place_names.pluck(:user_id).uniq).to eq([ workout.user_id ])
  end

  it "does not rewrite identical rows" do
    toponymy(**endpoints)
    described_class.new(workout:).call
    ids = workout.place_names.order(:position).pluck(:id)

    described_class.new(workout:).call

    expect(workout.place_names.order(:position).pluck(:id)).to eq(ids)
  end

  it "collapses a loop whose departure and arrival resolve alike" do
    record = toponymy(
      start_place: { "name" => "Rochelune", "kind" => "city" },
      finish_place: { "name" => "Rochelune", "kind" => "city" },
      markers: [
        { "distance" => 3_000.0, "name" => "C", "kind" => "hamlet", "rank" => 3 },
        { "distance" => 1_000.0, "name" => "A", "kind" => "hamlet", "rank" => 1 },
        { "distance" => 2_000.0, "name" => "B", "kind" => "hamlet", "rank" => 2 }
      ]
    )

    described_class.new(workout:).call

    expect(record.reload.places).to eq([
      { "name" => "Rochelune", "kind" => "city" },
      { "name" => "A", "kind" => "hamlet" },
      { "name" => "B", "kind" => "hamlet" }
    ])
  end

  it "falls back to the markers alone without endpoints" do
    record = toponymy(
      start_place: {},
      finish_place: {},
      markers: [ { "distance" => 2_000.0, "name" => "Cimefroide", "kind" => "town", "rank" => 1 } ]
    )

    described_class.new(workout:).call

    expect(record.reload.places).to eq([ { "name" => "Cimefroide", "kind" => "town" } ])
  end

  it "ignores malformed markers" do
    record = toponymy(
      **endpoints,
      markers: [
        { "distance" => "nope", "name" => "Nowhere", "kind" => "town", "rank" => 1 },
        { "distance" => 2_000.0, "name" => "", "kind" => "town", "rank" => 2 }
      ]
    )

    described_class.new(workout:).call

    expect(record.reload.places.pluck("name")).to eq(%w[Valmorin Rochelune])
  end

  it "clears a stale selection when nothing is usable" do
    stale = [ { "name" => "Old", "kind" => "village" } ]
    record = toponymy(
      start_place: {},
      finish_place: {},
      markers: [],
      places: stale,
      places_algorithm_version: 0
    )
    workout.update_columns(places: stale)

    described_class.new(workout:).call

    expect(record.reload.places).to eq([])
    expect(record.places_algorithm_version).to eq(described_class::ALGORITHM_VERSION)
    expect(workout.reload.places).to eq([])
    expect(workout.place_names).to be_empty
  end

  it "leaves an unusable toponymy untouched" do
    record = toponymy(status: "pending", **endpoints)

    described_class.new(workout:).call

    expect(record.reload.places).to eq([])
    expect(workout.reload.places).to eq([])
    expect(workout.place_names).to be_empty
  end

  it "returns without a toponymy" do
    expect { described_class.new(workout:).call }.not_to change { workout.reload.places }
  end
end
