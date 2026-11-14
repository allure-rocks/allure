# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stats" do
  let(:user) { create(:user) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  it "requires authentication" do
    get by_time_stats_path
    expect(response).to redirect_to(new_session_path)

    get by_sport_stats_path
    expect(response).to redirect_to(new_session_path)
  end

  it "shows an empty state with no workouts" do
    sign_in_as

    get by_time_stats_path
    expect(response.body).to include(I18n.t("stats.empty.title"))

    get by_sport_stats_path
    expect(response.body).to include(I18n.t("stats.empty.title"))
  end

  it "shows per-sport tables with periods and values" do
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running, distance: 5000)
    sign_in_as

    get by_time_stats_path(time: "month")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("stats.metrics.total_distance"))
    expect(response.body).to include(I18n.l(workout.started_at.to_date, format: :month_year))
  end

  it "localizes table periods and chart locale in French" do
    running = catalog_sport("running")
    create(:workout, user:, sport: running, distance: 5000, started_at: Time.zone.parse("2026-02-15 08:00:00"))
    sign_in_as

    get by_time_stats_path(time: "month")

    expect(response.body).to include("février 2026")
    expect(response.body).not_to include("February 2026")
    expect(response.body).to include("data-stats-chart-locale-value=\"fr\"")
  end

  it "hides masked metrics per sport display" do
    create(:workout, user:, sport: catalog_sport("running"))
    sign_in_as

    get by_time_stats_path(time: "month")

    expect(response.body).to include(I18n.t("stats.metrics.average_pace"))
    expect(response.body).not_to include(I18n.t("stats.metrics.average_speed"))
  end

  it "renders rowing average pace over 500 m and hides its speed column" do
    create(:workout, user:, sport: catalog_sport("rowing"), distance: 5_000, duration: 1_250,
                     moving_time: 1_200, pause_time: 50, average_pace: 240, average_speed: 4.16)
    sign_in_as

    get by_time_stats_path(time: "month")

    expect(response.body).to include(I18n.t("stats.metrics.average_pace"))
    expect(response.body).to include(I18n.t("units.pace.per_500m"))
    expect(response.body).not_to include(I18n.t("stats.metrics.average_speed"))
  end

  it "formats values in the viewer's unit system" do
    user.update!(unit_system: "imperial")
    create(:workout, user:, sport: create(:sport), distance: 1609.344)
    sign_in_as

    get by_time_stats_path(time: "month")

    expect(response.body).to include("mi")
    expect(response.body).not_to include("km")
  end

  it "shows only the current user's stats" do
    other = create(:user)
    create(:workout, user: other, sport: create(:sport), distance: 9000)
    sign_in_as

    get by_time_stats_path(time: "month")

    expect(response.body).to include(I18n.t("stats.empty.title"))
  end

  it "serves JSON buckets with private cache headers" do
    create(:workout, user:, sport: create(:sport))
    sign_in_as

    get by_time_stats_path(time: "month", format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    buckets = JSON.parse(response.body)["buckets"]
    expect(buckets.length).to eq(1)
    expect(buckets.first).to include("period", "sport_id", "total_workouts", "total_distance")
  end

  it "serves JSON sports rollup" do
    create(:workout, user:, sport: create(:sport))
    sign_in_as

    get by_sport_stats_path(format: :json)

    expect(response).to have_http_status(:ok)
    sports = JSON.parse(response.body)["sports"]
    expect(sports.length).to eq(1)
    expect(sports.first).to include("sport_id", "total_workouts")
    expect(sports.first).not_to have_key("period")
  end

  it "returns 404 for unknown granularity or sport" do
    sign_in_as

    get by_time_stats_path(time: "decade")
    expect(response).to have_http_status(:not_found)

    get by_time_stats_path(time: "month", sport_id: 0)
    expect(response).to have_http_status(:not_found)
  end
end
