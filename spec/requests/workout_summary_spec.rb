# frozen_string_literal: true

require "rails_helper"

# The owner's assistant summary card and its actions (docs/dev/AI.md §7,
# DESIGN.md §10.26).
RSpec.describe "Workout assistant summary", :assistant do
  include ActiveJob::TestHelper

  let(:user) { create(:user, ai_enabled: true) }
  let(:workout) { create(:workout, user:, started_at: 2.days.ago) }

  it "shows the verified text, the attribution and the proposed title" do
    create(:workout_summary, :ready, workout:)
    workout.update!(title_source: "default")
    sign_in_as(user)

    get workout_path(workout)

    expect(response.body).to include("Vous avez parcouru 62,4 km avec 850 m de dénivelé.")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("assistant.notice")))
    expect(response.body).to include(I18n.t("workouts.summary.proposed_title", title: "Le tour du lac"))
    expect(response.body).to include(I18n.t("workouts.summary.regenerate"))
  end

  it "offers to write a missing summary" do
    sign_in_as(user)

    get workout_path(workout)

    expect(response.body).to include(I18n.t("workouts.summary.empty"))
    expect(response.body).to include(I18n.t("workouts.summary.generate"))
  end

  it "shows the pending skeleton" do
    create(:workout_summary, workout:, status: "pending")
    sign_in_as(user)

    get workout_path(workout)

    expect(response.body).to include(I18n.t("workouts.summary.pending"))
  end

  it "is never rendered for a reader, and not without consent" do
    create(:workout_summary, :ready, workout:)
    sign_in_as(create(:user))

    get workout_path(workout)
    expect(response.body).not_to include(I18n.t("workouts.summary.title"))

    sign_in_as(user)
    user.update!(ai_enabled: false)
    get workout_path(workout)
    expect(response.body).not_to include(I18n.t("workouts.summary.title"))
  end

  it "requests a generation and throttles a second request" do
    sign_in_as(user)

    expect { post workout_summary_path(workout) }.to have_enqueued_job(Workouts::GenerateSummaryJob)
    expect(response).to redirect_to(workout_path(workout))
    expect(flash[:notice]).to eq(I18n.t("workouts.summary.requested"))
    expect(workout.reload.assistant_summary).to be_pending

    expect { post workout_summary_path(workout) }.not_to have_enqueued_job(Workouts::GenerateSummaryJob)
    expect(flash[:notice]).to eq(I18n.t("workouts.summary.throttled"))
  end

  it "refuses another account's workout" do
    sign_in_as(create(:user))

    post workout_summary_path(workout)

    expect(response).to have_http_status(:not_found)
  end

  it "applies the proposed title and stops proposing it" do
    create(:workout_summary, :ready, workout:)
    workout.update!(title_source: "default")
    sign_in_as(user)

    post workout_apply_summary_title_path(workout)

    expect(response).to redirect_to(workout_path(workout))
    expect(flash[:notice]).to eq(I18n.t("workouts.summary.title_applied"))
    expect(workout.reload).to have_attributes(title: "Le tour du lac", title_source: "owner")

    get workout_path(workout)
    expect(response.body).not_to include(I18n.t("workouts.summary.proposed_title", title: "Le tour du lac"))
  end
end
