# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Map track smoothing" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  before { create(:track_segment, workout:, position: 0) }

  it "renders the workout smoothing control with the account preference" do
    owner.update!(smooth_tracks: true, track_smoothing_level: "strong")
    sign_in_as(owner)

    get workout_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-map-smoothing-value="strong"')
    expect(response.body).to include('data-map-smoothing-level-value="strong"')
    expect(response.body).to include('data-map-smoothing-control-value="true"')
    expect(response.body).to include(%(data-map-smoothing-persist-url-value="#{settings_appearance_path}"))
    expect(response.body).to include("Options de la carte")
  end

  it "renders the recorded geometry for an account that never enabled smoothing" do
    sign_in_as(owner)

    get workout_path(workout)

    expect(response.body).to include('data-map-smoothing-value="off"')
    expect(response.body).to include('data-map-smoothing-level-value="medium"')
    expect(response.body).to include('data-map-smoothing-control-value="true"')
  end

  it "smoothes course maps at the medium level without a toggle" do
    segment = create(:segment, user: owner, visibility: "public")
    sign_in_as(owner)

    get segment_path(segment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-map-smoothing-value="medium"')
    expect(response.body).to include('data-map-smoothing-control-value="false"')
    expect(response.body).not_to include("Options de la carte")
  end
end
