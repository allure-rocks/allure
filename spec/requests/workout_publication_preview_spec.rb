# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout publication preview" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner, title: "Shareable ride", description: "A fine outing") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  def preview(profile_param = profile, headers: { "Accept" => "application/json" })
    get publication_preview_workout_path(workout), params: { publishing_profile_id: profile_param.id }, headers: headers
  end

  # The fields the publish page lists as shared by `profile`, from the
  # per-profile data the publish form swaps in on a profile change.
  def shared_fields
    profile
    get new_publication_workout_path(workout)
    form = Nokogiri::HTML(response.body).at_css("form[data-publication-preview-readiness-value]")
    JSON.parse(form["data-publication-preview-readiness-value"]).fetch(profile.id.to_s).fetch("shared")
  end

  def preview_html(profile_param = profile)
    preview(profile_param, headers: { "Accept" => "text/html" })
  end

  it "redirects anonymous visitors to sign in" do
    preview

    expect(response).to redirect_to(new_session_path)
  end

  it "returns 404 for another user's workout" do
    other = create(:user)
    sign_in_as(other)

    preview

    expect(response).to have_http_status(:not_found)
  end

  it "renders in the requested locale rather than the account locale" do
    sign_in_as(owner)

    get publication_preview_workout_path(workout), params: { publishing_profile_id: profile.id, locale: "en" },
        headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["preview_text"]).to include("exactly what will be shared")
  end

  it "shares the record badge and lists records when the profile enables them" do
    profile.update!(settings: profile.settings.merge("records" => true))
    sign_in_as(owner)

    preview(profile)
    expect(JSON.parse(response.body)["preview_text"]).to include(I18n.t("publishing_profiles.settings.records"))

    expect(shared_fields).to include(I18n.t("publishing_profiles.settings.records"))
  end

  it "names and shows the recording device only when the profile enables it" do
    workout.update!(source: "Garmin Edge 530")
    sign_in_as(owner)

    preview
    expect(JSON.parse(response.body)["preview_text"]).not_to include(I18n.t("publishing_profiles.settings.device"))
    expect(shared_fields).not_to include(I18n.t("publishing_profiles.settings.device"))

    profile.update!(settings: profile.settings.merge("device" => true))

    preview
    expect(JSON.parse(response.body)["preview_text"]).to include(I18n.t("publishing_profiles.settings.device"))
    expect(shared_fields).to include(I18n.t("publishing_profiles.settings.device"))
  end

  it "returns 404 for another user's profile" do
    other = create(:user)
    foreign = create(:publishing_profile, :without_endpoint_masks, user: other)
    sign_in_as(owner)

    get publication_preview_workout_path(workout), params: { publishing_profile_id: foreign.id }

    expect(response).to have_http_status(:not_found)
    expect(WorkoutPublication.count).to eq(0)
  end

  it "previews the followers profile whatever restricted federation says" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
    followers = create(:publishing_profile, :followers, :without_endpoint_masks, user: owner)
    sign_in_as(owner)

    preview(followers)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("ready" => true)
  end

  it "renders the exact candidate projection without persisting anything" do
    sign_in_as(owner)

    expect {
      preview
    }.to change(WorkoutPublication, :count).by(0)
    .and change(ActiveStorage::Blob, :count).by(0)
    .and change(ActiveStorage::Attachment, :count).by(0)
    .and change(FederationOutboxEvent, :count).by(0)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")

    body = JSON.parse(response.body)
    expect(body).to include("ready" => true, "blocking_error" => nil)
    expect(body["title"]).to eq("Shareable ride")
    expect(body["description"]).to eq("A fine outing")
    expect(body["sport"]).to be_present
    expect(body["started_at"]).to be_present
    expect(body["metrics"]).to be_an(Array)
    expect(body["metrics"].map { |metric| metric["key"] }).to include("distance")
    expect(body["route"]).to include("included" => true)
    expect(body["route"]["segments_count"]).to be_positive
    expect(body["route"]["geojson"]["type"]).to eq("FeatureCollection")
    expect(body["route"]["summary"]).to be_present
    expect(body["route"]["points"]).to be_present
    expect(body["gpx"]).to include("included" => false, "ready" => true)
    expect(body["route_image"]).to include("included" => true, "ready" => true)
    expect(body["preview_text"]).to eq(ApplicationController.helpers.publication_preview_text(profile))
    expect(body["labels"]).to include("title", "description", "sport", "started", "metrics", "route", "media")
  end

  it "reports an excluded route image when the profile disables it" do
    profile.update!(settings: profile.settings.merge("route_image" => false))
    sign_in_as(owner)

    preview

    body = JSON.parse(response.body)
    expect(body["route_image"]).to include("included" => false, "ready" => true)
  end

  it "matches the stored publication projection for the same profile" do
    sign_in_as(owner)
    preview
    previewed = JSON.parse(response.body)

    publication = Workouts::Publisher.new(user: owner, workout:, profile:).call!
    view = Workouts::PublicationView.new(publication)
    formatter_class = Class.new do
      include WorkoutsHelper
      include ActionView::Helpers::SanitizeHelper
      include ActionView::Helpers::TagHelper
      include ActionView::Helpers::OutputSafetyHelper
      include ActionView::Helpers::TranslationHelper
      include ActionView::Helpers::NumberHelper

      def current_user = nil
    end
    stub_const("PreviewFormatter", formatter_class)
    formatter = PreviewFormatter.new
    expected_metrics = formatter.workout_metric_items(view).to_h do |item|
      [ item.fetch(:key).to_s, formatter.strip_tags(formatter.workout_metric_value(item)) ]
    end

    expect(previewed["title"]).to eq(publication.representation["title"])
    expect(previewed["description"]).to eq(publication.representation["description"])
    expect(previewed["metrics"].to_h { |metric| [ metric["key"], metric["value"] ] }).to eq(expected_metrics)
    expect(previewed["metrics"].map { |metric| metric["key"] }).to match_array(publication.representation.fetch("metrics", {}).keys)
    expect(previewed["route"]["geojson"]).to eq(publication.representation["track"])
  end

  it "mirrors publication readiness for warnings" do
    sign_in_as(owner)
    preview
    previewed = JSON.parse(response.body)
    readiness = Workouts::PublicationReadiness.new(user: owner, workout:, profile:).call

    expect(previewed["ready"]).to eq(readiness.ready?)
    expect(previewed["warnings"]).to eq(
      readiness.warnings.map { |warning| I18n.t("workouts.publish.warnings.#{warning}") }
    )
  end

  it "reports media readiness without creating blobs" do
    profile.update!(settings: profile.settings.merge("gpx" => true, "route_image" => true))
    sign_in_as(owner)

    expect { preview }.to change(ActiveStorage::Blob, :count).by(0)

    body = JSON.parse(response.body)
    expect(body["gpx"]).to include("included" => true, "ready" => true)
    expect(body["route_image"]).to include("included" => true, "ready" => true)
  end

  it "blocks publishing when included media fails to generate" do
    profile.update!(settings: profile.settings.merge("gpx" => true))
    allow_any_instance_of(Allure::Federation::Privacy::SanitizedGpxBuilder).to receive(:call).and_raise(StandardError, "gpx exploded")
    sign_in_as(owner)

    preview

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["ready"]).to be(false)
    expect(body["gpx"]).to include("included" => true, "ready" => false)
    expect(WorkoutPublication.count).to eq(0)
  end

  it "returns a blocking error without persisting anything" do
    create(:track_segment, workout:,
           points: [
             { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074 },
             { "t" => 60, "d" => 100.0, "lat" => 45.0715, "lon" => 6.4080 },
             { "t" => 120, "d" => 200.0, "lat" => 45.0722, "lon" => 6.4086 },
             { "t" => 180, "d" => 300.0, "lat" => 45.0728, "lon" => 6.4092 }
           ])
    profile.update!(settings: PublishingProfile::DEFAULT_SETTINGS.merge("mask_start" => true, "mask_finish" => false))
    sign_in_as(owner)

    expect { preview }.to change(WorkoutPublication, :count).by(0)
      .and change(ActiveStorage::Blob, :count).by(0)

    expect(response).to have_http_status(:unprocessable_content)
    body = JSON.parse(response.body)
    expect(body["ready"]).to be(false)
    expect(body["blocking_error"]).to be_present
  end

  # The workout page lists what a profile shares instead of projecting it
  # (DESIGN.md §19.1): the endpoint answers JSON only.
  it "no longer renders an HTML preview" do
    sign_in_as(owner)

    preview_html

    expect(response).to have_http_status(:not_acceptable)
  end
end
