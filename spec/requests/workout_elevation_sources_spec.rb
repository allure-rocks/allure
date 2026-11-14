# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout elevation source" do
  let(:user) { create(:user) }
  let(:sport) { catalog_sport("running") }
  let(:workout) { create(:workout, user:, sport:) }

  before { sign_in_as(user) }

  it "records the requested source and enqueues the switch" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)

      expect { patch workout_elevation_source_path(workout), params: { elevation_source: "dem" } }
        .to have_enqueued_job(Workouts::ApplyElevationSourceJob).with(workout, "dem")

      expect(response).to redirect_to(workout_path(workout, anchor: "section-profile"))
      expect(workout.reload.elevation_source_requested).to eq("dem")
    end
  end

  it "refuses a source the account did not opt in to" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      expect { patch workout_elevation_source_path(workout), params: { elevation_source: "dem" } }
        .not_to have_enqueued_job(Workouts::ApplyElevationSourceJob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(workout.reload.elevation_source_requested).to be_nil
    end
  end

  it "refuses when the instance has no provider" do
    with_env("ELEVATION_BASE_URL" => nil) do
      user.update!(elevation_enrichment_enabled: true)

      expect { patch workout_elevation_source_path(workout), params: { elevation_source: "dem" } }
        .not_to have_enqueued_job(Workouts::ApplyElevationSourceJob)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "refuses an unknown source" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)

      patch workout_elevation_source_path(workout), params: { elevation_source: "gps" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(workout.reload.elevation_source_requested).to be_nil
    end
  end

  it "is not available to another account" do
    sign_in_as(create(:user))

    patch workout_elevation_source_path(workout), params: { elevation_source: "dem" }

    expect(response).to have_http_status(:not_found)
  end

  it "clears the request when the queue rejects the job" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)
      allow(Workouts::ApplyElevationSourceJob).to receive(:perform_later).and_raise("queue unavailable")

      patch workout_elevation_source_path(workout), params: { elevation_source: "dem" }

      expect(response).to redirect_to(workout_path(workout, anchor: "section-profile"))
      expect(workout.reload.elevation_source_requested).to be_nil
    end
  end

  it "offers the service switch in the header menu on the owner page" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)
      create(:workout_elevation, workout:, status: "ready")

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      menu = response.parsed_body.at_css(".allure-workout-header .dropdown-menu")
      expect(menu.text).to include(I18n.t("workouts.elevation.menu.switch_to_dem"))
      expect(menu.at_css("form[action='#{workout_elevation_source_path(workout)}'] input[value='dem']")).to be_present
      expect(response.body).not_to include('id="elevation-source"')
    end
  end

  it "offers the device switch and the estimated badge once the terrain profile is active" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)
      workout.update!(elevation_source: "dem")
      create(:workout_elevation, workout:, status: "ready")

      get workout_path(workout)

      menu = response.parsed_body.at_css(".allure-workout-header .dropdown-menu")
      expect(menu.text).to include(I18n.t("workouts.elevation.menu.switch_to_device"))
      expect(menu.at_css("form[action='#{workout_elevation_source_path(workout)}'] input[value='device']")).to be_present
      expect(response.body).to include(I18n.t("workouts.elevation.estimated_badge"))
    end
  end

  it "keeps the pending state in the menu while a switch request stands" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)
      workout.update!(elevation_source_requested: "dem")

      get workout_path(workout)

      menu = response.parsed_body.at_css(".allure-workout-header .dropdown-menu")
      expect(menu.text).to include(I18n.t("workouts.elevation.pending"))
      expect(menu.at_css("form[action='#{workout_elevation_source_path(workout)}']")).to be_nil
    end
  end

  it "keeps the switch available to retry after a failed enrichment" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)
      create(:workout_elevation, workout:, status: "failed")

      get workout_path(workout)

      menu = response.parsed_body.at_css(".allure-workout-header .dropdown-menu")
      expect(menu.text).to include(I18n.t("workouts.elevation.failed"))
      expect(menu.at_css("form[action='#{workout_elevation_source_path(workout)}'] input[value='dem']")).to be_present
    end
  end

  it "hides the switch from an owner who did not opt in" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      get workout_path(workout)

      expect(response.body).not_to include(I18n.t("workouts.elevation.menu.switch_to_dem"))
    end
  end

  it "hides the switch for a workout with no recorded profile" do
    with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
      user.update!(elevation_enrichment_enabled: true)
      workout.update!(recorded_elevation: false, elevation_source: "dem")
      create(:workout_elevation, workout:, status: "ready")

      get workout_path(workout)

      expect(response.body).not_to include(I18n.t("workouts.elevation.menu.switch_to_device"))
    end
  end

  describe "the elevation-absence notice in the summary" do
    let(:bare_workout) { create(:workout, user:, sport:, min_elevation: nil, max_elevation: nil) }

    it "explains that the instance does not estimate elevation" do
      with_env("ELEVATION_BASE_URL" => nil) do
        get workout_path(bare_workout)

        expect(response.body).to include('id="elevation-notice"')
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.provider_missing")))
        expect(response.body).not_to include(settings_elevation_path)
      end
    end

    it "names the disabled account setting and links to it" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        get workout_path(bare_workout)

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.opt_out")))
        expect(response.body).to include(settings_elevation_path)
      end
    end

    it "offers the estimate action while no terrain profile exists" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        user.update!(elevation_enrichment_enabled: true)

        get workout_path(bare_workout)

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.idle")))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.estimate")))
        expect(response.body).to include(workout_elevation_source_path(bare_workout))
      end
    end

    it "offers a retry after a failed enrichment" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        user.update!(elevation_enrichment_enabled: true)
        create(:workout_elevation, workout: bare_workout, status: "failed")

        get workout_path(bare_workout)

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.failed")))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.retry")))
        expect(response.body).to include(workout_elevation_source_path(bare_workout))
      end
    end

    it "reports an unavailable enrichment" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        user.update!(elevation_enrichment_enabled: true)
        create(:workout_elevation, workout: bare_workout, status: "unavailable")

        get workout_path(bare_workout)

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.unavailable")))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.retry")))
      end
    end

    it "keeps the pending state while a request stands" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        user.update!(elevation_enrichment_enabled: true)
        bare_workout.update!(elevation_source_requested: "dem")

        get workout_path(bare_workout)

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.pending")))
      end
    end

    it "names a sport that does not record elevation without an action" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        user.update!(elevation_enrichment_enabled: true)
        bare = create(:workout, user:, sport: catalog_sport("rowing"), min_elevation: nil, max_elevation: nil)

        get workout_path(bare)

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.elevation.notice.sport_without_elevation")))
        expect(response.body).not_to include(workout_elevation_source_path(bare))
        expect(response.body).not_to include(settings_elevation_path)
      end
    end

    it "does not render the notice when the workout has elevation" do
      with_env("ELEVATION_BASE_URL" => nil) do
        get workout_path(workout)

        expect(response.body).not_to include('id="elevation-notice"')
      end
    end

    it "enqueues the estimate from the summary notice" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        user.update!(elevation_enrichment_enabled: true)

        expect { patch workout_elevation_source_path(bare_workout), params: { elevation_source: "dem" } }
          .to have_enqueued_job(Workouts::ApplyElevationSourceJob).with(bare_workout, "dem")
      end
    end
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
