# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings data" do
  let(:user) { create(:user) }
  let(:other) { create(:user) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "redirects an anonymous visitor" do
    get settings_data_path

    expect(response).to redirect_to(new_session_path)
  end

  def with_original_file(workout)
    workout.original_file.attach(
      io: StringIO.new("bytes"), filename: "ride.fit", content_type: "application/octet-stream"
    )
    workout
  end

  context "signed in" do
    before { sign_in_as(user) }

    it "counts only the account's workouts" do
      with_original_file(create(:workout, user:, import_detection_version: 0))
      with_original_file(create(:workout, user: other, import_detection_version: 0))

      get settings_data_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.data.count", count: 1))
    end

    it "serves the live counters fragment without a layout" do
      get settings_data_path, headers: { "Turbo-Frame" => "settings-data-live" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<html")
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "enqueues a rebuild for the account" do
      with_original_file(create(:workout, user:, import_detection_version: 0))

      post settings_data_rebuild_path

      expect(response).to redirect_to(settings_data_path)
      expect(Workouts::UserBackfillJob).to have_been_enqueued.with(user.id, "rebuild")
      expect(AdminEvent.count).to eq(0)
    end

    it "does not enqueue when nothing is pending" do
      post settings_data_route_images_path

      expect(Workouts::UserBackfillJob).not_to have_been_enqueued
      expect(response).to redirect_to(settings_data_path)
      expect(flash[:notice]).to eq(I18n.t("settings.data.flash.route_images_current"))
    end

    it "enqueues the segment image sweep for the account" do
      create(:segment, user:, route_image_version: 0)

      post settings_data_segment_images_path

      expect(response).to redirect_to(settings_data_path)
      expect(Workouts::UserBackfillJob).to have_been_enqueued.with(user.id, "segment_images")
    end

    it "does not enqueue segment images when nothing is pending" do
      post settings_data_segment_images_path

      expect(Workouts::UserBackfillJob).not_to have_been_enqueued
      expect(flash[:notice]).to eq(I18n.t("settings.data.flash.segment_images_current"))
    end

    it "enqueues the loop reconciliation sweep for the account" do
      workout = create(:workout, user:, loop_reuse_version: 0)
      create(:segment, :loop, user:, source_workout: workout)

      post settings_data_loops_path

      expect(response).to redirect_to(settings_data_path)
      expect(Workouts::UserBackfillJob).to have_been_enqueued.with(user.id, "loops")
    end

    it "does not enqueue loop reconciliation when nothing is pending" do
      post settings_data_loops_path

      expect(Workouts::UserBackfillJob).not_to have_been_enqueued
      expect(flash[:notice]).to eq(I18n.t("settings.data.flash.loops_current"))
    end

    it "enqueues the recurring-route sweep for the account" do
      create(:workout, user:, route_suggestion_version: 0)

      post settings_data_route_suggestions_path

      expect(response).to redirect_to(settings_data_path)
      expect(Workouts::UserBackfillJob).to have_been_enqueued.with(user.id, "route_suggestions")
    end

    it "does not enqueue the recurring-route sweep when nothing is pending" do
      create(:workout, user:, route_suggestion_version: Segments::RouteSuggestionDetector::VERSION)

      post settings_data_route_suggestions_path

      expect(Workouts::UserBackfillJob).not_to have_been_enqueued
      expect(flash[:notice]).to eq(I18n.t("settings.data.flash.route_suggestions_current"))
    end

    it "refuses elevation without a provider" do
      post settings_data_elevation_path

      expect(Workouts::UserBackfillJob).not_to have_been_enqueued
      expect(flash[:notice]).to eq(I18n.t("settings.data.flash.elevation_current"))
    end
  end
end
