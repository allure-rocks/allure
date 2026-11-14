# frozen_string_literal: true

require "rails_helper"

# The redesigned personal hub: segmented sport and period selectors, calendar
# period windows, the figure strip and the intensity pulse, the sport mix,
# regularity, recent segment efforts and records.
RSpec.describe "Me hub" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let!(:running) { catalog_sport("running") }
  let!(:cycling) { catalog_sport("cycling") }

  around do |example|
    travel_to(Time.zone.local(2026, 9, 16, 12, 0, 0)) { example.run }
  end

  def tile_value(label)
    figure = Nokogiri::HTML(response.body).css(".hub-figure").find do |node|
      node.at_css(".hub-figure-label span")&.text&.strip == label
    end
    figure&.at_css(".hub-figure-value")&.text&.strip
  end

  def pulse_payload
    JSON.parse(Nokogiri::HTML(response.body).at_css("[data-hub-pulse-payload-value]")["data-hub-pulse-payload-value"])
  end

  def selector_labels
    Nokogiri::HTML(response.body).css(".hub-toolbar__sports input[name=sport_id]").map { |input| input["aria-label"] }
  end

  describe "toolbar" do
    before do
      create_list(:workout, 3, user:, sport: running, started_at: 2.days.ago)
      create(:workout, user:, sport: cycling, started_at: 3.days.ago)
      sign_in_as(user)
    end

    it "defaults to the last 30 days and ranks the sport pills by activity count" do
      get me_path

      expect(response.body).to include("30 derniers jours")
      expect(selector_labels).to eq([
        "Tous les sports — 4 activités",
        "#{running.translated_name} — 3 activités",
        "#{cycling.translated_name} — 1 activité"
      ])
      checked = Nokogiri::HTML(response.body).at_css(".hub-toolbar__sports input[name=sport_id][checked]")
      expect(checked["value"]).to eq("")
    end

    it "drops the sports without activity on the period but keeps the active one" do
      create(:workout, user:, sport: catalog_sport("walking"), started_at: 200.days.ago)

      get me_path
      expect(selector_labels.join).not_to include(catalog_sport("walking").translated_name)

      get me_path(sport_id: catalog_sport("walking").id)
      expect(selector_labels.last).to eq("#{catalog_sport('walking').translated_name} — 0 activités")
      checked = Nokogiri::HTML(response.body).css(".hub-toolbar__sports input[name=sport_id][checked]")
      expect(checked.map { |input| input["value"] }).to eq([ catalog_sport("walking").id.to_s ])

      get me_path(period: "all")
      expect(selector_labels.join).to include(catalog_sport("walking").translated_name)
    end

    it "offers every practiced sport in the phone sport select, keeping the period" do
      create(:workout, user:, sport: catalog_sport("walking"), started_at: 200.days.ago)

      get me_path(period: "year", sport_id: cycling.id)

      form = Nokogiri::HTML(response.body).at_css("form.hub-sport-select")
      expect(form["action"]).to eq(me_path)
      expect(form.at_css('input[name="period"]')["value"]).to eq("year")
      options = form.css("select[name=sport_id] option")
      expect(options.first["value"]).to eq("")
      expect(options.map(&:text)).to include(catalog_sport("walking").translated_name)
      expect(form.at_css("select[name=sport_id] option[selected]")["value"]).to eq(cycling.id.to_s)
    end

    it "submits the sport pills with the current period" do
      get me_path(period: "year")

      form = Nokogiri::HTML(response.body).at_css("form.hub-toolbar__sports")
      expect(form["action"]).to eq(me_path)
      expect(form.at_css("input[type=hidden][name=period]")["value"]).to eq("year")
    end

    it "keeps the sport in the period links" do
      get me_path(period: "year", sport_id: cycling.id)

      week = CGI.escapeHTML(me_path(period: "week", sport_id: cycling.id))
      expect(response.body).to include(%(href="#{week}"))
    end

    it "offers the same periods and sport in the phone select form" do
      get me_path(period: "year", sport_id: cycling.id)

      form = Nokogiri::HTML(response.body).at_css("form.hub-period-select")
      expect(form["action"]).to eq(me_path)
      expect(form.at_css('input[name="sport_id"]')["value"]).to eq(cycling.id.to_s)
      expect(form.css("select[name=period] option").map { |option| option["value"] }).to eq(MeController::PERIODS)
      expect(form.at_css("select[name=period] option[selected]")["value"]).to eq("year")
    end
  end

  describe "period windows" do
    before { sign_in_as(user) }

    it "counts the current calendar week and compares with the previous one" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 15, 8))
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 16, 8))
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 10, 8))

      get me_path(period: "week")

      expect(tile_value("Activités")).to eq("2")
      expect(response.body).to include("hub-delta--up")
    end

    it "counts the rolling last 30 days" do
      create(:workout, user:, sport: running, started_at: 10.days.ago)
      create(:workout, user:, sport: running, started_at: 40.days.ago)

      get me_path(period: "days30")

      expect(tile_value("Activités")).to eq("1")
    end

    it "counts the calendar year to date and compares with the same period last year" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 2, 1, 8))
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 1, 8))
      create(:workout, user:, sport: running, started_at: Time.zone.local(2025, 3, 1, 8))
      create(:workout, user:, sport: running, started_at: Time.zone.local(2025, 12, 20, 8))

      get me_path(period: "year")

      expect(tile_value("Activités")).to eq("2")
      expect(response.body).to include("hub-delta--up")
    end

    it "counts the whole history on Tout without a comparison" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2023, 6, 1, 8))
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 1, 8))

      get me_path(period: "all")

      expect(tile_value("Activités")).to eq("2")
      expect(response.body).not_to include("hub-delta")
    end

    it "follows the Sunday week start" do
      user.update!(week_start: "sunday")
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 13, 8))

      get me_path(period: "week")

      expect(tile_value("Activités")).to eq("1")
    end

    it "falls back to the last 30 days on an unknown period" do
      create(:workout, user:, sport: running, started_at: 10.days.ago)
      create(:workout, user:, sport: running, started_at: 40.days.ago)

      get me_path(period: "bogus")

      expect(tile_value("Activités")).to eq("1")
    end
  end

  describe "sport filter" do
    before do
      create(:workout, user:, sport: running, started_at: 2.days.ago, distance: 10_000, title: "Run session")
      create(:workout, user:, sport: cycling, started_at: 3.days.ago, distance: 30_000, title: "Ride session")
      sign_in_as(user)
    end

    it "scopes the summary tiles to the selected sport" do
      get me_path(sport_id: cycling.id)

      expect(tile_value("Distance")).to eq("30,0 km")
    end

    it "scopes the recent workouts to the selected sport" do
      get me_path(sport_id: running.id)

      expect(response.body).to include("Run session")
      expect(response.body).not_to include("Ride session")
    end

    it "scopes the records teaser to the selected sport" do
      get me_path(sport_id: cycling.id)

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?("Derniers records") }
      expect(card.text).to include(cycling.translated_name)
      expect(card.text).not_to include(running.translated_name)
      expect(card.at_css(".ti-trophy")).to be_nil
    end

    it "passes the sport to the calendar dataset and to the day links" do
      get me_path(sport_id: cycling.id)

      expect(response.body).to include("sport_id=#{cycling.id}")
      expect(response.body).to include("sports%5B%5D=#{cycling.id}")
    end

    it "offers the calendar metrics as radios and as the phone select" do
      get me_path

      page = Nokogiri::HTML(response.body)
      expect(page.css('input[name="calendar_metric"]').map { |input| input["value"] }).to eq(%w[duration distance count])
      select = page.at_css("select.hub-calendar-metric-select")
      expect(select.css("option").map { |option| option["value"] }).to eq(%w[duration distance count])
      expect(select.at_css("option[selected]")["value"]).to eq("duration")
    end

    it "offers the sport-mix metrics as radios and as the phone select" do
      get me_path

      page = Nokogiri::HTML(response.body)
      expect(page.css('input[name="mix_metric"]').map { |input| input["value"] }).to eq(%w[duration distance workouts])
      select = page.at_css("select.hub-mix-metric-select")
      expect(select.css("option").map { |option| option["value"] }).to eq(%w[duration distance workouts])
      expect(select.at_css("option[selected]")["value"]).to eq("duration")
    end

    it "ignores a sport the viewer never practiced" do
      other = catalog_sport("rowing")

      get me_path(sport_id: other.id)

      expect(response.body).not_to include("sport_id=#{other.id}")
      expect(selector_labels.first).to start_with("Tous les sports")
    end
  end

  describe "intensity pulse" do
    it "renders the four figures, one weekly pulse with its payload, and the screen-reader values" do
      workout = create(:workout, user:, sport: running, started_at: 1.day.ago, distance: 10_000, duration: 3660, moving_time: 3600, pause_time: 60, ascent: 120)
      sign_in_as(user)

      get me_path(period: "week")

      page = Nokogiri::HTML(response.body)
      expect(page.css(".hub-figure").size).to eq(4)
      expect(tile_value("Activités")).to eq("1")
      expect(tile_value("Temps")).to eq("1 h")
      expect(page.css('[data-controller="hub-pulse"]').size).to eq(1)
      expect(page.css('[data-hub-pulse-target="charts"]').size).to eq(1)

      payload = pulse_payload
      expect(payload["granularity"]).to eq("week")
      expect(payload["points"].size).to eq(1)
      expect(payload["points"].first).to include(
        "score" => 100, "rest" => false, "in_period" => true, "peak" => true,
        "detail" => "1 activité · 10,0 km · 120 m · 1 h"
      )
      # A week holding one activity opens it, not a one-row list.
      expect(payload["points"].first["url"]).to eq(workout_path(workout))
      expect(payload["older_url"]).to be_nil

      reading = page.at_css(".hub-pulse-reading").text
      expect(reading).not_to include("Pic")
      expect(reading).to include("Semaine du 14 septembre", "1 activité · 10,0 km · 120 m · 1 h")
      expect(response.body).to include("1 semaine active sur 1")
      expect(response.body).not_to include("Voir les valeurs")
      expect(page.css("table tbody tr").map { |row| row.css("td").last.text.strip }).to include("1 activité · 10,0 km · 120 m · 1 h")
    end

    it "keeps every week of the history and highlights only the selected period" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 1, 8), distance: 8_000, duration: 2700, moving_time: 2700, pause_time: 0)
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 8, 8), distance: 12_000, duration: 3600, moving_time: 3600, pause_time: 0)
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 15, 8), distance: 5_000, duration: 1800, moving_time: 1800, pause_time: 0)
      sign_in_as(user)

      get me_path(period: "week")

      payload = pulse_payload
      expect(payload["points"].size).to eq(3)
      expect(payload["points"].map { |point| point["in_period"] }).to eq([ false, false, true ])
      expect(payload["points"].last).to include("rest" => false, "peak" => true)
    end

    it "names the peak only when the period spans more than one week" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 8, 8), distance: 8_000, duration: 2700, moving_time: 2700, pause_time: 0)
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 15, 8), distance: 5_000, duration: 1_800, moving_time: 1_800, pause_time: 0)
      sign_in_as(user)

      get me_path(period: "days30")
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".hub-pulse-reading").text).to include("Pic :")
      # No week is chosen yet: the peak is information, and the callout and
      # its button wait for a selection.
      expect(page.at_css('[data-hub-pulse-target="callout"]').key?("hidden")).to be(true)
      expect(page.at_css('[data-hub-pulse-target="open"]').text.strip).to be_empty
      expect(pulse_payload["points"].find { |point| point["peak"] }).to include(
        "open_label" => "Voir l'activité"
      )
      expect(pulse_payload["points"].find { |point| point["peak"] }["url"]).to start_with("/workouts/")

      get me_path(period: "week")
      reading = Nokogiri::HTML(response.body).at_css(".hub-pulse-reading").text
      expect(reading).not_to include("Pic")
      expect(reading).to include("Semaine du 14 septembre", "1 activité · 5,0 km")
    end

    it "names a week's sports from the second one on" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 15, 8), distance: 5_000, duration: 1800, moving_time: 1800, pause_time: 0)
      create(:workout, user:, sport: cycling, started_at: Time.zone.local(2026, 9, 16, 8), distance: 20_000, duration: 3600, moving_time: 3600, pause_time: 0)
      sign_in_as(user)

      get me_path(period: "week")

      expect(pulse_payload["points"].last["detail"]).to include("2 sports")
    end

    it "carries one explanatory hint naming the grain, the history and the scoring" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)
      sign_in_as(user)

      get me_path

      buttons = Nokogiri::HTML(response.body).css(".hub-tile-hint")

      expect(buttons.size).to eq(1)
      expect(buttons.first["data-controller"]).to eq("tooltip")
      expect(buttons.first["aria-label"]).to include("Chaque capsule est une semaine", "à parts égales", "30 jours précédents")
      expect(buttons.first["data-bs-title"]).to include("semaine la plus forte de votre historique")
    end

    it "serves the older weekly windows scored against the same basis" do
      create(:workout, user:, sport: running, started_at: Time.zone.local(2023, 6, 1, 8), distance: 10_000, duration: 3600, moving_time: 3600, pause_time: 0, ascent: 200)
      create(:workout, user:, sport: running, started_at: Time.zone.local(2026, 9, 1, 8), distance: 5_000, duration: 1800, moving_time: 1800, pause_time: 0, ascent: 50)
      sign_in_as(user)

      get me_path(period: "all")

      initial = pulse_payload
      expect(initial["points"].size).to eq(104)
      expect(initial["older_url"]).to include("period=all", "before=")
      expect(response.body).to match(/2 semaines actives sur \d+/)

      get initial["older_url"]

      expect(response).to have_http_status(:ok)
      chunk = JSON.parse(response.body)
      expect(chunk["points"]).to be_present
      expect(chunk["points"].first["label"]).to eq(I18n.l(Date.new(2023, 5, 29), format: :short_year))
      expect(chunk["points"].first).to include("in_period" => true, "peak" => true)
      expect(chunk["older_url"]).to be_nil
    end

    it "carries the sport filter in the older windows URL" do
      create(:workout, user:, sport: cycling, started_at: Time.zone.local(2023, 6, 1, 8))
      create(:workout, user:, sport: cycling, started_at: Time.zone.local(2026, 9, 1, 8))
      create(:workout, user:, sport: cycling, started_at: Time.zone.local(2026, 9, 2, 8))
      sign_in_as(user)

      get me_path(period: "all", sport_id: cycling.id)

      expect(pulse_payload["older_url"]).to include("sport_id=#{cycling.id}")
      active = pulse_payload["points"].find { |point| !point["rest"] }
      expect(active["url"]).to include("sports%5B%5D=#{cycling.id}")
    end

    it "rejects an invalid older-window cursor" do
      create(:workout, user:, sport: running, started_at: 1.day.ago)
      sign_in_as(user)

      get pulse_me_path(period: "all", before: "not-a-date")

      expect(response).to have_http_status(:bad_request)
    end

    it "serves an empty window for an account without history" do
      sign_in_as(user)

      get pulse_me_path(period: "all")

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["points"]).to eq([])
      expect(JSON.parse(response.body)["older_url"]).to be_nil
    end

    it "says so when the filtered window holds no activity" do
      create(:workout, user:, sport: running, started_at: 60.days.ago)
      sign_in_as(user)

      get me_path(period: "week")

      expect(response.body).to include("Aucune activité sur la période.")
      expect(response.body).not_to include("Pic :")
      expect(pulse_payload["points"].none? { |point| point["peak"] }).to be(true)
      expect(pulse_payload["points"].last["in_period"]).to be(true)
    end

    it "keeps the figures but omits the pulse and its hint when there is no workout" do
      sign_in_as(user)

      get me_path

      page = Nokogiri::HTML(response.body)
      expect(page.css(".hub-figure").size).to eq(4)
      expect(tile_value("Activités")).to eq("0")
      expect(page.css('[data-controller="hub-pulse"]')).to be_empty
      expect(page.css(".hub-tile-hint")).to be_empty
    end
  end

  describe "sport mix" do
    before { sign_in_as(user) }

    it "renders the pie with its metric selector and table when several sports are practiced" do
      create(:workout, user:, sport: running, started_at: 2.days.ago, distance: 10_000)
      create(:workout, user:, sport: cycling, started_at: 3.days.ago, distance: 30_000)

      get me_path

      expect(response.body).to include("Répartition des sports", "data-hub-pie-payload-value=")
      expect(response.body).to include("Voir les données", "Part")
      expect(Nokogiri::HTML(response.body).css('[data-hub-pie-target="chart"], .hub-mix-chart').size).to eq(1)
    end

    it "hides the pie when a single sport is filtered" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)
      create(:workout, user:, sport: cycling, started_at: 3.days.ago)

      get me_path(sport_id: cycling.id)

      expect(response.body).not_to include("Répartition des sports")
    end

    it "hides the pie with a single practiced sport" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)

      get me_path

      expect(response.body).not_to include("Répartition des sports")
    end

    it "builds the all-time pie beyond the daily window" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)
      create(:workout, user:, sport: cycling, started_at: 200.days.ago)

      get me_path(period: "all")

      expect(response.body).to include("Répartition des sports")
    end
  end

  describe "regularity" do
    it "renders the week figures and the statistics link" do
      create(:workout, user:, sport: running, started_at: 2.days.ago, distance: 10_000)
      sign_in_as(user)

      get me_path

      expect(response.body).to include("Régularité", "Cette semaine", "Moyenne 4 sem.")
      expect(response.body).to include(%(href="#{stats_path}"))
    end
  end

  describe "recent workouts" do
    it "lists the twelve latest as fully clickable cards without a footer" do
      create_list(:workout, 14, user:, sport: running, started_at: 3.days.ago)

      sign_in_as(user)
      get me_path

      cards = Nokogiri::HTML(response.body).css(".row-cards > .col-sm-6")
      recent = cards.select { |card| card.at_css("a.stretched-link") }
      expect(recent.size).to eq(12)
      expect(recent).to all(satisfy { |card| card.at_css(".card-footer").nil? })
      expect(recent.first.at_css(".card").attr("class")).to include("position-relative", "workout-card--linked")
      expect(recent.first.at_css(".card-body .d-flex").attr("class")).to include("align-items-start")
      expect(recent.first.attr("class")).to include("col-xxl-3")
    end

    it "uses smart dates, human durations and the sport-preferred average" do
      pace_sport = create(:sport, slug: "running_pace", label: "Running pace", pace_speed_display: "pace")
      started = 1.day.ago.in_time_zone(user.time_zone).change(hour: 7, min: 30)
      create(:workout, user:, sport: pace_sport, started_at: started,
                       distance: 12_000, duration: 5100, moving_time: 5000, pause_time: 100,
                       average_pace: 425, ascent: 320)

      sign_in_as(user)
      get me_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.at_css("a.stretched-link") }
      expect(card.text).to include("Hier 07:30")
      expect(card.text).to include(I18n.t("units.duration.hours_minutes", hours: 1, minutes: 25))
      expect(card.text).to include(I18n.t("units.pace.per_km"))
      expect(card.text).not_to include(I18n.t("workouts.show.metrics.moving_time"))
    end

    it "carries the sport on the tile as an accessible, linked mark instead of a printed name" do
      create(:workout, user:, sport: running, title: "Named run", started_at: 2.days.ago)

      sign_in_as(user)
      get me_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.at_css("a.stretched-link") }
      tile = card.at_css("a.sport-tile--link")
      expect(tile["aria-label"]).to eq(running.translated_name)
      expect(tile["data-bs-title"]).to eq(running.translated_name)
      expect(tile["data-controller"]).to eq("tooltip")
      expect(card.text).not_to include(running.translated_name)
      expect(card.text).to include("Named run")
    end

    def view_all_href
      link = Nokogiri::HTML(response.body).css("a").find do |anchor|
        anchor.text.strip == I18n.t("me.recent.view_all")
      end
      link["href"]
    end

    it "carries the sport filter and the period into the view-all link" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)
      create(:workout, user:, sport: cycling, started_at: 3.days.ago)

      sign_in_as(user)
      get me_path(sport_id: cycling.id, period: "year")

      expect(view_all_href).to eq(workouts_path(sports: [ cycling.id ], period: "year"))
    end

    it "carries the default period into the plain view-all link" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)

      sign_in_as(user)
      get me_path

      expect(view_all_href).to eq(workouts_path(period: "days30"))
    end
  end

  describe "recent segments" do
    it "lists the latest efforts with their time and leaderboard rank" do
      workout = create(:workout, user:, sport: running, started_at: 2.days.ago)
      segment = create(:segment, user:, sport: running, name: "Col du Test", visibility: "public")
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(user), status: "active")
      create(:segment_effort, workout:, segment:, user:, sport: running, elapsed_time: 125,
                              personal_best: true)
      slower = create(:workout, user:, sport: running, started_at: 1.day.ago)
      create(:segment_effort, workout: slower, segment:, user:, sport: running, elapsed_time: 140)
      sign_in_as(user)

      get me_path

      expect(response.body).to include("Segments récents", "Col du Test", "2:05", "2:20")
      rows = Nokogiri::HTML(response.body).css("table tbody tr").select { |row| row.text.include?("Col du Test") }
      cells = rows.map { |row| row.css("td").map { |cell| cell.text.squish } }
      expect(cells.map { |row| row[-2] })
        .to eq([ "#{I18n.t('medals.personal_place.second', record: 'Col du Test')} 2 / 2",
                 "#{I18n.t('medals.record', record: 'Col du Test')} 1 / 2" ])
      # The board column wears the numbered medal (visible numeral, spoken rank).
      expect(cells.map { |row| row[-1] }).to eq([ "—", "1#{I18n.t('medals.rank', rank: 1)} / 1" ])
      expect(rows.last.at_css("td:last-child .allure-medal--gold")).to be_present
      expect(rows.last.at_css("td:nth-last-child(2) i.ti-trophy.allure-medal--gold")).to be_present
      expect(rows.first.at_css("td:nth-last-child(2) i.ti-trophy.allure-medal--silver")).to be_present
    end
  end

  describe "removed cards" do
    it "no longer renders the trend, sport-breakdown and equipment cards" do
      create(:workout, user:, sport: running, started_at: 2.days.ago)
      sign_in_as(user)

      get me_path

      expect(response.body).not_to include("Par sport", "Équipement actif", "12 dernières semaines")
    end
  end

  describe "empty hub" do
    it "keeps the import empty state and the records teaser, without charts or regularity" do
      sign_in_as(user)

      get me_path

      expect(response.body).to include("Rien ici pour l&#39;instant")
      expect(response.body).to include(%(href="#{records_path}"))
      expect(response.body).not_to include("Régularité")
    end
  end

  describe "latest records" do
    it "lists the best-effort records beside the classic ones and hides the types the sport cannot express" do
      running.update!(pace_speed_display: "pace")
      workout = create(:workout, user:, sport: running, started_at: 2.days.ago)
      Record.find_or_initialize_by(user:, sport: running, record_type: "FD")
        .update!(workout:, value: 10_000, workout_started_at: workout.started_at)
      Record.find_or_initialize_by(user:, sport: running, record_type: "AS")
        .update!(workout:, value: 3.2, workout_started_at: workout.started_at)
      EffortRecord.find_or_initialize_by(user:, sport: running, distance_key: "km5")
        .update!(workout:, distance_meters: 5_000, duration_seconds: 1_500, workout_started_at: workout.started_at)
      Record.where(user:).where.not(record_type: %w[FD AS]).delete_all
      sign_in_as(user)

      get me_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?("Derniers records") }
      expect(card.text).to include(I18n.t("records.types.fd"), I18n.t("records.distances.km5"), "25:00")
      expect(card.text).not_to include(I18n.t("records.types.as"))
    end

    it "opens the records page on the sport the hub is filtered to" do
      create(:workout, user:, sport: running)
      sign_in_as(user)

      get me_path
      expect(response.body).to include(%(href="#{records_path}"))
      expect(response.body).not_to include("records?sport_id")

      get me_path(sport_id: running.id)
      expect(response.body).to include(%(href="#{records_path(sport_id: running.id)}"))
    end
  end
end
