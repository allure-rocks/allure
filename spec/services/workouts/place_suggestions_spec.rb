# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PlaceSuggestions do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  def place_names(owner, names)
    workout = create(:workout, user: owner)
    names.each_with_index do |name, index|
      create(:workout_place_name, workout:, user: owner, name:, position: index)
    end
  end

  it "lists the owner's places by descending frequency then name" do
    place_names(user, %w[Rochelune Cimefroide])
    place_names(user, %w[Rochelune])
    place_names(other, %w[Rochelune Dinant])

    expect(described_class.new(user:).call).to eq(%w[Rochelune Cimefroide])
  end

  it "matches a case-insensitive substring" do
    place_names(user, %w[Rochelune Valmorin Cimefroide])

    expect(described_class.new(user:, query: "val").call).to eq(%w[Valmorin])
    expect(described_class.new(user:, query: "ROC").call).to eq(%w[Rochelune])
  end

  it "escapes LIKE wildcards" do
    place_names(user, [ "100% ride", "100 km ride" ])

    expect(described_class.new(user:, query: "100%").call).to eq([ "100% ride" ])
  end

  it "bounds the number of suggestions" do
    3.times { |index| place_names(user, [ "Place #{index}" ]) }

    expect(described_class.new(user:, limit: 2).call.length).to eq(2)
  end
end
