# frozen_string_literal: true

require "rails_helper"

# M4 Slice 3 proofs: every data table follows the priority-column rule
# (DESIGN.md §12) — wide tables render as a real table and as a stacked card
# list (the workout analysis card switches between them on its own width),
# narrow tables stay tables but carry captions and scoped headers.
RSpec.describe "Slice 3 responsive tables" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def table_variant(body)
    body.include?("table-responsive d-none d-md-block") || body.include?("table-responsive allure-analysis-table")
  end
  def card_variant(body) = body.include?("allure-card-list")

  describe "workout laps and splits" do
    it "renders laps as a captioned table plus cards" do
      workout = create(:workout, user:, sport:)
      create(:track_segment, workout:)
      create(:lap, workout:, number: 1)
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).to include("<caption", "<th scope=")
      expect(table_variant(response.body)).to be(true)
      expect(card_variant(response.body)).to be(true)
    end

    it "renders splits with the partial flag in both variants" do
      workout = create(:workout, user:, sport:)
      create(:track_segment, workout:)
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).to include(I18n.t("workouts.show.splits.title"))
      expect(response.body.scan(I18n.t("workouts.show.splits.partial")).size).to be >= 2
    end
  end

  describe "segment efforts" do
    it "renders workout segment efforts as table plus cards" do
      workout = create(:workout, user:, sport:)
      create(:track_segment, workout:)
      segment = create(:segment, user:, sport:)
      create(:segment_effort, segment:, workout:, user:, sport:)
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).to include(I18n.t("workouts.show.segment_efforts.title"))
      expect(table_variant(response.body)).to be(true)
      expect(card_variant(response.body)).to be(true)
    end

    it "renders owner efforts with the workout title first in cards" do
      workout = create(:workout, user:, sport:, title: "Card title workout")
      segment = create(:segment, user:, sport:)
      create(:segment_effort, segment:, workout:, user:, sport:)
      sign_in_as(user)

      get segment_path(segment)

      expect(response.body).to include("Card title workout")
      expect(card_variant(response.body)).to be(true)
    end

    it "renders shared rows with rank and alias in cards" do
      owner = create(:user)
      athlete = create(:user)
      segment = create(:segment, user: owner, sport:, visibility: "public")
      workout = create(:workout, user: athlete, sport:)
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(athlete), status: "active")
      create(:segment_effort, segment:, workout:, user: athlete, sport:)
      expected_alias = Allure::Leaderboard::Alias.for(user_id: athlete.id, segment_id: segment.id, locale: I18n.locale)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response.body).to include(expected_alias)
      expect(response.body).to include("allure-medal--gold", I18n.t("medals.rank", rank: 1))
      expect(card_variant(response.body)).to be(true)
    end
  end

  describe "narrow tables" do
    it "keeps records as a captioned table with scoped headers" do
      create(:workout, user:, sport:, distance: 5_000)
      sign_in_as(user)

      get records_path

      expect(response.body).to include("<caption", "<th scope=")
      expect(response.body).not_to include("allure-card-list")
    end

    # DESIGN.md §12: a table is named by a <caption> or by aria-labelledby; the
    # sessions table is named by its card's visible title.
    it "keeps sessions as a table named by its card title" do
      sign_in_as(user)

      get settings_security_path

      expect(response.body).to include(%(aria-labelledby="sessions-title"), %(id="sessions-title"), "<th scope=")
      expect(response.body).not_to include("allure-card-list")
    end
  end

  describe "stats tables" do
    it "renders by_time buckets as table plus cards" do
      create(:workout, user:, sport:)
      sign_in_as(user)

      get by_time_stats_path(time: "month")

      expect(response.body).to include("<caption", "<th scope=")
      expect(table_variant(response.body)).to be(true)
      expect(card_variant(response.body)).to be(true)
    end

    it "renders by_sport totals as table plus cards" do
      create(:workout, user:, sport:)
      sign_in_as(user)

      get by_sport_stats_path

      expect(table_variant(response.body)).to be(true)
      expect(card_variant(response.body)).to be(true)
    end
  end

  describe "import entries" do
    it "renders entries as table plus cards" do
      batch = create(:workout_import_batch, user:, sport:)
      entry_workout = create(:workout, user:, sport:, distance: 2_500)
      create(:workout_import_entry, batch:, workout: entry_workout, status: "imported", position: 0)
      sign_in_as(user)

      get workout_import_path(batch)

      expect(response.body).to include("<caption", "<th scope=")
      expect(table_variant(response.body)).to be(true)
      expect(card_variant(response.body)).to be(true)
    end
  end
end
