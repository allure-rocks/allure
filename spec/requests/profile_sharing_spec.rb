# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Optional profile statistics and records" do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:sport) { catalog_sport("running") }
  let!(:workout) do
    create(:workout, user: owner, sport:, title: "Never shared title", source: "Never shared device",
                     started_at: Time.utc(2004, 3, 15, 6, 12), distance: 12_345, moving_time: 3_660,
                     duration: 4_000, pause_time: 340, ascent: 634, average_heart_rate: 157, average_power: 321)
  end

  before { sign_in_as(viewer) }

  def statistics_card = response.parsed_body.at_css("#profile-statistics-title")&.parent&.parent
  def records_card = response.parsed_body.at_css("#profile-records-title")&.parent&.parent

  def expect_no_source_details(card)
    expect(card.css("a, time")).to be_empty
    expect(card.to_html).not_to include(
      "Never shared title", "Never shared device", workout.to_param, workout.started_at.iso8601,
      I18n.l(workout.started_at.to_date), "average_heart_rate", "average_power", '"lat"', '"longitude"'
    )
  end

  def follow_viewer(status: "accepted", reverse: false)
    owner_actor = Federation::ActorProvisioner.new(user: owner).call!
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    create(:following, follower_actor: reverse ? owner_actor : viewer_actor,
                       followed_actor: reverse ? viewer_actor : owner_actor,
                       status:, accepted_at: (Time.current if status == "accepted"),
                       undone_at: (Time.current if status == "undone"))
  end

  def profile_queries(**params)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get profile_path(owner.username), params: }
    queries
  end

  def expect_no_private_queries(queries)
    expect(queries).not_to include(a_string_matching(/SUM\(/), a_string_matching(/FROM "(?:records|effort_records)"/))
  end

  it "shows neither block by default, even to the owner, and does not query private aggregates" do
    sign_in_as(owner)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get profile_path(owner.username) }

    expect(statistics_card).to be_nil
    expect(records_card).to be_nil
    expect(queries).not_to include(a_string_matching(/SUM\(/), a_string_matching(/FROM "(?:records|effort_records)"/))
  end

  it "shares full-history volumes with every member without sharing the activity or its records" do
    owner.update!(profile_statistics_audience: "members")

    get profile_path(owner.username)

    expect(response).to have_http_status(:ok)
    expect(statistics_card.text).to include(sport.translated_name, "12,35 km", "1 h 1 min")
    expect(records_card).to be_nil
    expect_no_source_details(statistics_card)
    expect(workout.active_publications).to be_empty

    get workout_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "shares personal winners and standard-distance best times without dates or source links" do
    owner.update!(profile_records_audience: "members")
    create(:effort_record, user: owner, sport:, workout:, distance_key: "km5", duration_seconds: 1_234)

    get profile_path(owner.username)

    expect(statistics_card).to be_nil
    expect(records_card.text).to include(sport.translated_name, I18n.t("records.types.fd"), I18n.t("records.distances.km5"), "20:34")
    expect(records_card.css(".ti-trophy, .allure-record-badge")).to be_empty
    expect_no_source_details(records_card)
  end

  it "places shared figures in the left rail even without a biography or published sport mix" do
    owner.update!(bio: nil, profile_statistics_audience: "members", profile_records_audience: "members")

    get profile_path(owner.username)

    page = response.parsed_body
    expect(page.at_css(".profile-layout--sidebar .profile-intro #profile-statistics-title")).to be_present
    expect(page.at_css(".profile-intro #profile-records-title")).to be_present
    expect(page.css(".profile-journal #profile-statistics-title, .profile-journal #profile-records-title")).to be_empty
    expect(statistics_card.css("[data-profile-radar-payload-value]").size).to eq(4)
    expect(statistics_card.css("table").size).to eq(4)
    expect(statistics_card.css("table").all? { |table| table.css("thead th").size == 2 }).to be(true)
  end

  it "provides native sport radios and complete sequential tables as the no-JavaScript baseline" do
    owner.update!(profile_records_audience: "members")
    create(:workout, user: owner, sport: catalog_sport("cycling"), distance: 54_321)

    get profile_path(owner.username)

    radios = records_card.css("input[type='radio'][name='profile_record_sport']")
    panels = records_card.css("[data-paged-panels-target='panel']")
    expect(radios.map { |radio| radio["value"] }).to eq(panels.map { |panel| panel["id"].delete_prefix("profile-records-") })
    expect(radios.size).to eq(2)
    expect(radios.count { |radio| radio.key?("checked") }).to eq(1)
    expect(records_card.at_css("[data-paged-panels-target='navigation']").key?("hidden")).to be(true)
    expect(records_card.css("details, summary, [data-paged-panels-target='panel'][hidden], [data-paged-panels-target='panel'][inert]")).to be_empty
    radios.each do |radio|
      panel = panels.find { |candidate| candidate["id"] == radio["aria-controls"] }
      expect(panel.at_css("table caption").text).to eq(radio["data-choice-name"])
      expect(records_card.at_css("##{panel['aria-labelledby']}").text).to include(radio["data-choice-name"])
    end
    expect_no_source_details(records_card)
  end

  it "pages measures independently of record sports, with raw totals and open data tables as the fallback" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members")
    create(:workout, user: owner, sport: catalog_sport("rowing"), distance: 5_000)

    get profile_path(owner.username)

    radios = statistics_card.css("input[type='radio'][name='profile_statistics_metric']")
    expect(radios.map { |radio| radio["value"] }).to eq(%w[total_workouts total_distance total_duration total_ascent])
    expect(radios.count { |radio| radio.key?("checked") }).to eq(1)
    expect(statistics_card.at_css("[data-paged-panels-target='navigation']").key?("hidden")).to be(true)
    expect(statistics_card.css("details[open]").size).to eq(4)
    expect(statistics_card.css("[data-paged-panels-target='panel'][hidden], [data-paged-panels-target='panel'][inert]")).to be_empty
    ascent = statistics_card.at_css("#profile-statistic-total_ascent")
    payload = JSON.parse(ascent["data-profile-radar-payload-value"])
    expect(payload.fetch("entries")).to eq([ { "name" => sport.translated_name, "value" => 634, "formatted" => "634 m" } ])
    expect(ascent.at_css("[data-profile-radar-target='chart']")["aria-hidden"]).to eq("true")
    expect(ascent.text).to include(I18n.t("profile.statistics.log_scale"))
    expect(records_card.css("input[name='profile_statistics_metric']")).to be_empty
    expect_no_source_details(statistics_card)
  end

  it "does not offer sport switching for a single sport" do
    owner.update!(profile_records_audience: "members")

    get profile_path(owner.username)

    expect(records_card.css("input[type='radio'], [data-paged-panels-target='navigation']")).to be_empty
    expect(records_card.css("[data-paged-panels-target='panel']").size).to eq(1)
    expect(records_card.text).not_to include(I18n.t("profile.records.swipe_hint"))
  end

  it "provides optional reading tooltips beside the same complete server-formatted tables" do
    owner.update!(profile_statistics_audience: "members")

    get profile_path(owner.username)

    statistics_card.css("[data-controller='profile-radar']").each do |panel|
      payload = JSON.parse(panel["data-profile-radar-payload-value"])
      label = panel.at_css("[data-profile-radar-target='label']")
      tooltip = panel.at_css("[data-profile-radar-target='tooltip']")
      expect(label.text).to eq(panel.at_css("table caption").text)
      expect(tooltip.key?("hidden")).to be(true)
      expect(tooltip["aria-hidden"]).to eq("true")
      expect(tooltip.at_css("[data-profile-radar-target='tooltipName']").text).to be_empty
      expect(tooltip.at_css("[data-profile-radar-target='tooltipValue']").text).to be_empty
      expect(panel.at_css("[data-profile-radar-target='visual']").key?("hidden")).to be(true)
      expect(panel.text).to include(I18n.t("profile.statistics.reading_hint"))
      expect(panel.css("tbody tr").map { |row| row.css("th, td").map(&:text) }).to eq(
        payload.fetch("entries").map { |entry| entry.values_at("name", "formatted") }
      )
    end
  end

  it "leaves no empty rail when nothing is shared and the biography is absent" do
    owner.update!(bio: nil)

    get profile_path(owner.username)

    expect(response.parsed_body.css(".profile-layout--sidebar, .profile-intro")).to be_empty
    expect(response.parsed_body.at_css("#profile-journal-title")).to be_present
  end

  it "keeps both whole-history blocks independent from publication sport and period filters" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members")
    create(:workout, user: owner, sport: catalog_sport("cycling"), title: "Another private outing", distance: 54_321)
    create(:workout, user: viewer, sport:, distance: 999_999)

    get profile_path(owner.username), params: { sport: "cycling", period: "week" }

    expect(statistics_card.text).to include("12,35 km", "54,32 km")
    expect(records_card.text).to include("12,35 km", "54,32 km")
    expect(statistics_card.text).not_to include("1 000", "1000", "999")
    expect(response.parsed_body.css("article.feed-item")).to be_empty
    expect(response.body).not_to include("Another private outing", "Never shared title")
  end

  it "withdraws either block on the next read without changing the other permission" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members")
    get profile_path(owner.username)
    expect(statistics_card).to be_present
    expect(records_card).to be_present

    sign_in_as(owner)
    patch settings_profile_path, params: { user: { profile_statistics_audience: "none" } }
    sign_in_as(viewer)
    get profile_path(owner.username)

    expect(statistics_card).to be_nil
    expect(records_card).to be_present

    sign_in_as(owner)
    patch settings_profile_path, params: { user: { profile_records_audience: "none" } }
    sign_in_as(viewer)
    get profile_path(owner.username)

    expect(statistics_card).to be_nil
    expect(records_card).to be_nil
  end

  it "formats the shared figures in the reader's units" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members")
    viewer.update!(unit_system: "imperial")

    get profile_path(owner.username)

    expect(statistics_card.text).to include("mi", "ft")
    expect(records_card.text).to include("mi")
    expect(statistics_card.text).not_to include("km")
    %w[distance ascent].each do |metric|
      panel = statistics_card.at_css("#profile-statistic-total_#{metric}")
      entry = JSON.parse(panel["data-profile-radar-payload-value"]).fetch("entries").sole
      expect(entry.fetch("value")).to eq(workout.public_send(metric))
      expect(panel.at_css("tbody td").text).to eq(entry.fetch("formatted"))
      expect(entry.fetch("formatted")).to include(metric == "distance" ? "mi" : "ft")
    end
  end

  it "does not expose a suspended account's optional blocks" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members", suspended_at: Time.current)

    get profile_path(owner.username)

    expect(statistics_card).to be_nil
    expect(records_card).to be_nil
  end

  it "still requires membership while both sharing permissions are enabled" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members")
    delete session_path

    get profile_path(owner.username)

    expect(response).to redirect_to(new_session_path)
  end

  context "with followers audiences" do
    before do
      owner.update!(profile_statistics_audience: "followers", profile_records_audience: "followers")
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
    end

    it "serves an accepted follower without enabling restricted federation or sharing the source" do
      follow_viewer

      get profile_path(owner.username)

      expect(statistics_card).to be_present
      expect(records_card).to be_present
      expect_no_source_details(statistics_card)
      expect_no_source_details(records_card)

      get workout_path(workout)
      expect(response).to have_http_status(:not_found)
    end

    %w[pending rejected undone].each do |status|
      it "embeds no figures, chart payload or records for a #{status} follower" do
        follow_viewer(status:)

        queries = profile_queries

        expect(statistics_card).to be_nil
        expect(records_card).to be_nil
        expect(response.parsed_body.css("[data-profile-radar-payload-value], .profile-records")).to be_empty
        expect_no_private_queries(queries)
      end
    end

    it "does not treat an account followed by the owner as the owner's follower" do
      follow_viewer(reverse: true)

      queries = profile_queries

      expect(statistics_card).to be_nil
      expect(records_card).to be_nil
      expect_no_private_queries(queries)
    end

    it "does not allow an unrelated member to override the audience through URL parameters" do
      queries = profile_queries(audience: "members", profile_statistics_audience: "members", user_id: owner.id)

      expect(statistics_card).to be_nil
      expect(records_card).to be_nil
      expect_no_private_queries(queries)
    end

    it "lets the owner read both shared sections" do
      sign_in_as(owner)

      get profile_path(owner.username)

      expect(statistics_card).to be_present
      expect(records_card).to be_present
    end

    it "withdraws both sections and their payloads on the next read after an unfollow" do
      following = follow_viewer
      get profile_path(owner.username)
      expect(statistics_card).to be_present
      expect(records_card).to be_present

      following.undo!
      queries = profile_queries

      expect(statistics_card).to be_nil
      expect(records_card).to be_nil
      expect(response.parsed_body.css("[data-profile-radar-payload-value]")).to be_empty
      expect_no_private_queries(queries)
    end
  end

  it "authorizes statistics and records separately for an unrelated reader" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "followers")
    queries = profile_queries
    expect(statistics_card).to be_present
    expect(records_card).to be_nil
    expect(queries).not_to include(a_string_matching(/FROM "(?:records|effort_records)"/))

    owner.update!(profile_statistics_audience: "followers", profile_records_audience: "members")
    queries = profile_queries
    expect(statistics_card).to be_nil
    expect(records_card).to be_present
    expect(response.parsed_body.css("[data-profile-radar-payload-value]")).to be_empty
    expect(queries).not_to include(a_string_matching(/SUM\(/))
  end

  it "applies an audience reduction made in settings on the next profile read" do
    owner.update!(profile_statistics_audience: "members", profile_records_audience: "members")
    get profile_path(owner.username)
    expect(statistics_card).to be_present
    expect(records_card).to be_present

    sign_in_as(owner)
    patch settings_profile_path, params: { user: { profile_statistics_audience: "followers", profile_records_audience: "followers" } }
    sign_in_as(viewer)
    queries = profile_queries

    expect(statistics_card).to be_nil
    expect(records_card).to be_nil
    expect_no_private_queries(queries)
  end

  context "with only a duration-only manual workout" do
    let!(:workout) do
      create(:workout, :manual, user: owner, sport: catalog_sport("fitness"), distance: 0, average_speed: 0, average_pace: nil)
    end

    it "offers count and duration without inventing distance or elevation" do
      owner.update!(profile_statistics_audience: "members")

      get profile_path(owner.username)

      expect(statistics_card.css("input[name='profile_statistics_metric']").map { |radio| radio["value"] }).to eq(%w[total_workouts total_duration])
      expect(statistics_card.css("[data-profile-radar-payload-value]").size).to eq(2)
      expect(statistics_card.text).to include("1 h")
    end
  end
end
