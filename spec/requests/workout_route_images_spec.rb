# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout route images" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  before do
    workout.route_image.attach(
      io: StringIO.new("\x89PNG\r\n\x1A\nroute".b),
      filename: "route.png",
      content_type: "image/png"
    )
  end

  it "proxies the PNG to its owner without exposing a storage URL" do
    sign_in_as(owner)

    get workout_route_image_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(response.body).to start_with("\x89PNG".b)
  end

  it "remains owner-only even when every visibility is public" do
    get workout_route_image_path(workout)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(create(:user))
    get workout_route_image_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 while generation is pending" do
    workout.route_image.purge
    sign_in_as(owner)

    get workout_route_image_path(workout)

    expect(response).to have_http_status(:not_found)
  end

  it "serves the dark variant and falls back to the attached one" do
    sign_in_as(owner)

    get workout_route_image_path(workout, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("route")

    workout.route_image_dark.attach(
      io: StringIO.new("\x89PNG\r\n\x1A\ndark".b),
      filename: "route-dark.png",
      content_type: "image/png"
    )

    get workout_route_image_path(workout, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to end_with("dark".b)
  end

  it "falls back to the dark variant when only it is attached" do
    workout.route_image.purge
    workout.route_image_dark.attach(
      io: StringIO.new("\x89PNG\r\n\x1A\ndark".b),
      filename: "route-dark.png",
      content_type: "image/png"
    )
    sign_in_as(owner)

    get workout_route_image_path(workout, theme: "light")

    expect(response).to have_http_status(:ok)
    expect(response.body).to end_with("dark".b)
  end

  it "does not expose the source image to a non-owner with a public publication" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)

    get workout_route_image_path(workout)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(owner)
    get workout_route_image_path(workout)
    expect(response).to have_http_status(:ok)
  end

  describe "regenerate" do
    it "enqueues a render for the owner and redirects back" do
      sign_in_as(owner)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      post workout_regenerate_route_image_path(workout)

      expect(response).to redirect_to(workout_path(workout))
      expect(Workouts::RenderRouteImageJob).to have_been_enqueued.with(workout)
    end

    it "requires a session and stays owner-only" do
      post workout_regenerate_route_image_path(workout)

      expect(response).to redirect_to(new_session_path)
      expect(Workouts::RenderRouteImageJob).not_to have_been_enqueued

      sign_in_as(create(:user))
      post workout_regenerate_route_image_path(workout)

      expect(response).to have_http_status(:not_found)
      expect(Workouts::RenderRouteImageJob).not_to have_been_enqueued
    end
  end

  it "returns 404 for malformed, unknown, and integer identifiers" do
    sign_in_as(owner)

    get workout_route_image_path(workout_id: "invalid")
    expect(response).to have_http_status(:not_found)

    get workout_route_image_path(workout_id: "2222222222222222222222")
    expect(response).to have_http_status(:not_found)

    get workout_route_image_path(workout_id: workout.id)
    expect(response).to have_http_status(:not_found)
  end
end
