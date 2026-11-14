# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout place suggestions" do
  let(:owner) { create(:user) }

  def place_names(user, names)
    workout = create(:workout, user:)
    names.each_with_index do |name, index|
      create(:workout_place_name, workout:, user:, name:, position: index)
    end
  end

  it "requires authentication" do
    get workout_place_suggestions_path

    expect(response).to redirect_to(new_session_path)
  end

  it "returns the owner's place names by frequency without caching" do
    place_names(owner, %w[Rochelune Cimefroide])
    place_names(owner, %w[Rochelune])
    place_names(create(:user), %w[Secret])
    sign_in_as(owner)

    get workout_place_suggestions_path

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.parsed_body).to eq("places" => %w[Rochelune Cimefroide])
    expect(response.body).not_to include("Secret")
    expect(response.body).not_to include("latitude", "longitude")
  end

  it "narrows the suggestions with the query" do
    place_names(owner, %w[Rochelune Valmorin])
    sign_in_as(owner)

    get workout_place_suggestions_path(q: "val")

    expect(response.parsed_body).to eq("places" => %w[Valmorin])
  end
end
