# frozen_string_literal: true

require "rails_helper"

# The owner's assistant summary block and its actions (docs/dev/AI.md §7,
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
    expect(response.body).to include(I18n.t("workouts.summary.proposed_title", title: "Le tour du lac"))

    # The attribution is the small info icon at the end, not a paragraph; the
    # action lives in the header's ⋯ menu, never in the block.
    section = response.parsed_body.at_css("#section-summary-ai")
    expect(section.text).not_to include(I18n.t("workouts.summary.title"))
    expect(section.text).not_to include(I18n.t("workouts.show.regenerate_summary"))
    info = section.at_css(".allure-workout-assistant__info")
    expect(info["aria-label"]).to eq(I18n.t("assistant.notice"))
    expect(info["data-bs-title"]).to eq(I18n.t("assistant.notice"))

    menu = response.parsed_body.at_css(".allure-workout-header .dropdown-menu")
    expect(menu.text).to include(I18n.t("workouts.show.regenerate_summary"))
  end

  it "disables the summary action while the request floor lasts" do
    create(:workout_summary, :ready, workout:, requested_at: 1.minute.ago)
    sign_in_as(user)

    get workout_path(workout)

    menu = response.parsed_body.at_css(".allure-workout-header .dropdown-menu")
    button = menu.css("button").find { it.text == I18n.t("workouts.show.regenerate_summary") }
    expect(button["disabled"]).to be_present
    expect(button["title"]).to include("min")
  end

  # DESIGN.md §10.26, §20.3: the description leads the figures card's text
  # block; the summary takes its place only without one, unless the account
  # asked for both.
  describe "alongside the owner's description" do
    before { workout.update!(description: "Le lac était calme.") }

    it "keeps the description alone by default" do
      create(:workout_summary, :ready, workout:)
      sign_in_as(user)

      get workout_path(workout)

      card = response.parsed_body.at_css(".allure-workout-summary")
      expect(card.at_css(".allure-workout-copy").text).to include("Le lac était calme.")
      expect(card.at_css("#workout-summary-#{workout.id}")).to be_nil
      expect(card.text).not_to include("Vous avez parcouru 62,4 km")
    end

    it "shows both, description first, when the account asked for it" do
      user.update!(ai_summary_with_description: true)
      create(:workout_summary, :ready, workout:)
      sign_in_as(user)

      get workout_path(workout)

      card = response.parsed_body.at_css(".allure-workout-summary")
      expect(card.at_css(".allure-workout-copy").text).to include("Le lac était calme.")
      expect(card.at_css("#workout-summary-#{workout.id}").text).to include("Vous avez parcouru 62,4 km")
      expect(card.text.index("Le lac était calme.")).to be < card.text.index("Vous avez parcouru 62,4 km")
    end

    it "shows no assistant block while the summary is absent" do
      sign_in_as(user)

      get workout_path(workout)

      card = response.parsed_body.at_css(".allure-workout-summary")
      expect(card.text).to include("Le lac était calme.")
      expect(card.text).not_to include(I18n.t("workouts.summary.empty"))
      expect(card.text).not_to include(I18n.t("workouts.summary.generate"))
    end
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
    expect(response.parsed_body.at_css("#section-summary-ai")).to be_nil

    sign_in_as(user)
    user.update!(ai_enabled: false)
    get workout_path(workout)
    expect(response.parsed_body.at_css("#section-summary-ai")).to be_nil
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
