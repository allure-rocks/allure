# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Records" do
  let(:user) { create(:user) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  it "requires authentication" do
    get records_path

    expect(response).to redirect_to(new_session_path)
  end

  it "shows an empty state with no records" do
    sign_in_as

    get records_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("records.index.empty_title"))
  end

  it "shows only the current user's records" do
    other = create(:user)
    create(:workout, user: other, sport: create(:sport), distance: 9000)
    sign_in_as

    get records_path

    expect(response.body).to include(I18n.t("records.index.empty_title"))
    expect(response.body).not_to include("9.0 km", "9,0 km")
  end

  it "groups records by sport with values and set-on dates" do
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running, distance: 5000)
    sign_in_as

    get records_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("records.types.fd"))
    expect(response.body).to include(workout_path(workout))
    expect(response.body).to include(I18n.l(workout.started_at.to_date))
  end

  it "shows pace records and hides speed records for pace sports" do
    create(:workout, user:, sport: catalog_sport("running"))
    sign_in_as

    get records_path

    expect(response.body).to include(I18n.t("records.types.ap"), I18n.t("records.types.bp"))
    expect(response.body).not_to include(I18n.t("records.types.as"), I18n.t("records.types.ms"))
  end

  it "shows speed records and hides pace records for speed sports" do
    create(:workout, user:, sport: catalog_sport("cycling"))
    sign_in_as

    get records_path

    expect(response.body).to include(I18n.t("records.types.as"), I18n.t("records.types.ms"))
    expect(response.body).not_to include(I18n.t("records.types.ap"), I18n.t("records.types.bp"))
  end

  it "renders rowing pace records over 500 m and hides its speed records" do
    create(:workout, user:, sport: catalog_sport("rowing"), average_pace: 233, best_pace: 217)
    sign_in_as

    get records_path

    expect(response.body).to include(I18n.t("records.types.ap"), I18n.t("records.types.bp"))
    expect(response.body).to include("1:57 /500m", "1:49 /500m")
    expect(response.body).not_to include(I18n.t("records.types.as"), I18n.t("records.types.ms"))
  end

  it "hides ascent records for sports that do not record elevation" do
    flat = create(:sport, records_elevation: false)
    create(:workout, user:, sport: flat, ascent: 100)
    expect(Record.where(user:, sport: flat, record_type: "HA").count).to eq(1)
    sign_in_as

    get records_path

    expect(response.body).not_to include(I18n.t("records.types.ha"))
  end

  it "shows every type for pace-and-speed sports" do
    both = create(:sport, pace_speed_display: "pace_and_speed")
    create(:workout, user:, sport: both)
    sign_in_as

    get records_path

    %w[ap as bp fd ha ld ms].each do |type|
      expect(response.body).to include(I18n.t("records.types.#{type}"))
    end
  end

  it "formats values in the viewer's unit system" do
    user.update!(unit_system: "imperial")
    # One mile, so metric kilometres must not appear.
    create(:workout, user:, sport: create(:sport), distance: 1609.344)
    sign_in_as

    get records_path

    # Visible page text only: random short IDs in links may contain "km".
    text = Nokogiri::HTML(response.body).at_css("#main-content").text
    expect(text).to match(/\bmi\b/)
    expect(text).not_to match(/\bkm\b/)
  end

  it "shows the best-efforts block per sport" do
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running, distance: 5000)
    create(:effort_record, user:, sport: running, workout:,
                           distance_key: "km5", distance_meters: 5000, duration_seconds: 1500)
    sign_in_as

    get records_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("records.efforts.title"))
    expect(response.body).to include(I18n.t("records.distances.km5"))
    expect(response.body).to include("25:00")
    expect(response.body).to include(workout_path(workout))
  end

  it "shows the rowing best-efforts distances in profile order" do
    rowing = catalog_sport("rowing")
    workout = create(:workout, user:, sport: rowing, distance: 2000)
    create(:effort_record, user:, sport: rowing, workout:,
                           distance_key: "km2", distance_meters: 2000, duration_seconds: 400)

    sign_in_as

    get records_path

    expect(response.body).to include(I18n.t("records.distances.km2"))
    expect(response.body).to include("6:40")
  end

  it "shows the biggest-climb record" do
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running)
    create(:detected_lap, :climb, workout:, ascent: 180.0)
    Records::RecomputeService.new(user:, sport: running).call
    sign_in_as

    get records_path

    expect(response.body).to include(I18n.t("records.types.mc"))
    expect(response.body).to include(I18n.t("units.elevation.m", count: 180))
  end

  it "lists records without a per-row cup: every row is already a record" do
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running, distance: 5000)
    create(:effort_record, user:, sport: running, workout:,
                           distance_key: "km5", distance_meters: 5000, duration_seconds: 1500)
    sign_in_as

    get records_path

    rows = Nokogiri::HTML(response.body).css("table tbody tr")
    record_row = rows.find { |row| row.text.include?(I18n.t("records.types.fd")) }
    effort_row = rows.find { |row| row.text.include?(I18n.t("records.distances.km5")) }
    expect(record_row).to be_present
    expect(effort_row).to be_present
    expect(rows.flat_map { |row| row.css(".ti-trophy") }).to be_empty
  end

  it "shows only the current user's effort records" do
    other = create(:user)
    running = catalog_sport("running")
    workout = create(:workout, user: other, sport: running, distance: 5000)
    create(:effort_record, user: other, sport: running, workout:,
                           distance_key: "km5", distance_meters: 5000, duration_seconds: 1500)
    sign_in_as

    get records_path

    expect(response.body).not_to include(I18n.t("records.distances.km5"))
  end

  it "pages one sport at a time with native radios and every table as the no-JavaScript baseline" do
    running = catalog_sport("running")
    cycling = catalog_sport("cycling")
    create(:workout, user:, sport: running, distance: 5_000)
    create(:workout, user:, sport: cycling, distance: 20_000)
    sign_in_as

    get records_path

    page = Nokogiri::HTML(response.body)
    radios = page.css("input[type='radio'][name='record_sport']")
    panels = page.css("[data-paged-panels-target='panel']")
    expect(radios.map { |radio| radio["value"] }).to eq(panels.map { |panel| panel["id"].delete_prefix("records-") })
    expect(radios.size).to eq(2)
    expect(radios.count { |radio| radio.key?("checked") }).to eq(1)
    expect(page.at_css("[data-paged-panels-target='navigation']").key?("hidden")).to be(true)
    expect(page.css("[data-paged-panels-target='panel'][hidden], [data-paged-panels-target='panel'][inert]")).to be_empty
    expect(page.at_css("[data-paged-panels-fit-value='true']")).to be_present
    radios.each do |radio|
      panel = panels.find { |candidate| candidate["id"] == radio["aria-controls"] }
      expect(panel).to be_present
      expect(panel.at_css("table caption").text).to include(radio["data-choice-name"])
    end
  end

  it "opens on the most practised sport" do
    running = catalog_sport("running")
    cycling = catalog_sport("cycling")
    2.times { create(:workout, user:, sport: running, distance: 5_000) }
    create(:workout, user:, sport: cycling, distance: 20_000)
    sign_in_as

    get records_path

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='record_sport'][checked]")["value"]).to eq("running")
    expect(page.css("[data-paged-panels-target='panel']").first["id"]).to eq("records-running")
  end

  it "opens on the sport named by sport_id" do
    running = catalog_sport("running")
    cycling = catalog_sport("cycling")
    create(:workout, user:, sport: running, distance: 5_000)
    create(:workout, user:, sport: cycling, distance: 20_000)
    sign_in_as

    # Cycling leads the catalog order on a tie, so asking for running proves
    # the parameter decides rather than the default.
    get records_path(sport_id: running.id)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='record_sport'][checked]")["value"]).to eq("running")
  end

  it "falls back to the first sport when sport_id names none of them" do
    running = catalog_sport("running")
    cycling = catalog_sport("cycling")
    2.times { create(:workout, user:, sport: running, distance: 5_000) }
    create(:workout, user:, sport: cycling, distance: 20_000)
    sign_in_as

    get records_path(sport_id: 0)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='record_sport'][checked]")["value"]).to eq("running")
  end

  it "offers no sport selector for a single sport" do
    create(:workout, user:, sport: catalog_sport("running"), distance: 5_000)
    sign_in_as

    get records_path

    page = Nokogiri::HTML(response.body)
    expect(page.css("input[name='record_sport'], [data-paged-panels-target='navigation']")).to be_empty
    expect(page.css("[data-paged-panels-target='panel']").size).to eq(1)
    expect(page.text).not_to include(I18n.t("records.index.swipe_hint"))
  end

  it "lists the classic records in the record type order, not in insertion order" do
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running, distance: 5_000)
    average_pace = Record.find_by!(user:, sport: running, record_type: "AP")
    average_pace.destroy!
    Record.create!(user:, sport: running, record_type: "AP", value: average_pace.value,
                   workout:, workout_started_at: workout.started_at)
    sign_in_as

    get records_path

    labels = Nokogiri::HTML(response.body).at_css("#records-running table")
      .css("tbody tr td:first-child").map { |cell| cell.text.strip }
    expected = Record.where(user:, sport: running).to_a
      .select { |record| Record.visible_type?(record.record_type, record.sport) }
      .sort_by { |record| Record::TYPES.index(record.record_type) }
      .map { |record| I18n.t("records.types.#{record.record_type.downcase}") }
    expect(labels).to eq(expected)
    expect(labels.first).to eq(I18n.t("records.types.ap"))
    expect(labels.size).to be > 1
  end
end
