# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workouts" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def sign_in_user(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  def imported_workout(sport:)
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/galibier.gpx")),
      filename: "galibier.gpx",
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: upload).call!
  end

  # The elevation provider reads the environment at call time
  # (Allure::Elevation::Config); a test toggles it for one example.
  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe "GET /workouts" do
    it "requires authentication" do
      get workouts_path
      expect(response).to redirect_to(new_session_path)
    end

    it "leads an empty list to the import page" do
      sign_in_user

      get workouts_path

      expect(response.body).to include(I18n.t("workouts.index.empty.title"))
      expect(response.body).to include(%(href="#{new_workout_import_path}"))
      expect(response.body).to include(I18n.t("workouts.index.new_button"))
    end

    it "marks a commute workout with its badge" do
      create(:workout, user: user, sport: sport, title: "Daily commute", commute: true)
      sign_in_user

      get workouts_path

      expect(response.body).to include("Daily commute", I18n.t("workouts.commute.badge"))
    end

    it "shows the derived place on the owner's cards and table" do
      create(:workout, user: user, sport: sport, title: "Placed ride",
                       places: [ { "name" => "Valmorin", "kind" => "village" }, { "name" => "Rochelune", "kind" => "city" } ])
      sign_in_user

      get workouts_path
      expect(response.body).to include("Valmorin · Rochelune")

      get workouts_path(view: "table")
      expect(response.body).to include("Valmorin · Rochelune")
    end

    it "filters the list by a recorded place name" do
      near = create(:workout, user: user, sport: sport, title: "Near Rochelune")
      create(:workout_place_name, workout: near, user: user, name: "Rochelune", kind: "city", position: 0)
      elsewhere = create(:workout, user: user, sport: sport, title: "Elsewhere")
      create(:workout_place_name, workout: elsewhere, user: user, name: "Cimefroide", kind: "town", position: 0)
      sign_in_user

      get workouts_path(place: "roc")

      expect(response.body).to include("Near Rochelune")
      expect(response.body).not_to include("Elsewhere")
    end

    it "filters on a recorded place that is not among the displayed three" do
      deep = create(:workout, user: user, sport: sport, title: "Deep marker",
                    places: [ { "name" => "Valmorin", "kind" => "village" }, { "name" => "A", "kind" => "hamlet" },
                              { "name" => "Rochelune", "kind" => "city" } ])
      create(:workout_place_name, workout: deep, user: user, name: "B", kind: "hamlet", position: 1)
      sign_in_user

      get workouts_path(place: "B")

      expect(response.body).to include("Deep marker")
    end

    it "renders the place as a removable counted chip" do
      workout = create(:workout, user: user, sport: sport)
      create(:workout_place_name, workout:, user: user, name: "Rochelune", kind: "city", position: 0)
      sign_in_user

      get workouts_path(place: "Rochelune")

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".allure-filter-bar button.filter-toggle .badge").text.strip).to eq("1")
      chip = page.css(".allure-filter-bar .badge").find { |badge| badge.text.include?("Rochelune") }
      expect(chip).to be_present
      expect(chip.at_css("a[href='#{workouts_path}']")).to be_present
    end

    it "leads the header with the section tile and the count, and keeps the rare filters in a drawer" do
      create(:workout, user: user, sport: sport, title: "Visible ride")
      sign_in_user

      get workouts_path

      page = Nokogiri::HTML(response.body)
      header = page.at_css(".page-header")
      expect(header.at_css(".sport-tile .ti-activity")).to be_present
      expect(header.at_css("h1").text.strip).to eq(I18n.t("workouts.index.title"))
      expect(header.at_css(".page-pretitle")).to be_nil
      expect(header.at_css("[aria-live='polite']").text.strip).to eq(I18n.t("workouts.index.filters.count", count: 1))
      expect(header.at_css("a[href='#{new_workout_import_path}']")).to be_nil
      expect(header.at_css("a[href*='view=table']")).to be_present
      expect(header.at_css("button.filter-toggle")).to be_nil

      controls = page.at_css(".allure-filter-bar__controls")
      toggle = controls.at_css("button.filter-toggle[data-bs-toggle='offcanvas'][data-bs-target='#workout-filters']")
      expect(toggle).to be_present
      expect(controls.at_css("select[name=period]")).to be_present
      expect(controls.at_css("select[name=sort]")).to be_present

      panel = page.at_css("#workout-filters")
      expect(panel["class"]).to include("offcanvas")
      expect(panel["class"]).not_to include("show")
      expect(page.at_css("form #workout-filters")).to be_present
      expect(panel.css("select[name=publication], select[name=commute], input[name=place], input[name=q]").size).to eq(4)
      expect(page.at_css(".allure-filter-bar noscript")).to be_present
      expect(panel.at_css(".allure-sport-filter, select[name=period], select[name=sort]")).to be_nil
    end

    it "never opens the drawer by itself, badges its own filters, and counts the filtered result against the total" do
      create(:workout, user: user, sport: sport, title: "Filtered ride")
      create(:workout, user: user, sport: sport, title: "Other run")
      sign_in_user

      get workouts_path(sports: [ sport.id.to_s ], q: "ride")

      page = Nokogiri::HTML(response.body)
      toggle = page.at_css(".allure-filter-bar button.filter-toggle")
      expect(toggle.at_css(".badge").text.strip).to eq("1")
      expect(page.at_css("#workout-filters")["class"]).not_to include("show")

      clear = page.css("a").find { |link| link.text.strip == I18n.t("workouts.index.filters.clear") }
      expect(clear).to be_present
      expect(clear.ancestors("#workout-filters")).to be_empty

      count = page.at_css(".page-header [aria-live='polite']")
      expect(count.text.strip).to eq(I18n.t("workouts.index.filters.count_filtered", count: 1, total: 2))
    end

    it "never badges the toggle nor chips a sport-only selection, but offers to clear it" do
      create(:workout, user: user, sport: sport, title: "Selected sport ride")
      sign_in_user

      get workouts_path(sports: [ sport.id.to_s ])

      page = Nokogiri::HTML(response.body)
      toggle = page.at_css(".allure-filter-bar button.filter-toggle")
      expect(toggle.at_css(".badge")).to be_nil
      expect(page.at_css("#workout-filters")["class"]).not_to include("show")

      chip = page.css(".allure-filter-bar .badge").find { |badge| badge.text.include?(sport.label) }
      expect(chip).to be_nil
      expect(page.css("a").map { |link| link.text.strip }).to include(I18n.t("workouts.index.filters.clear"))
    end

    it "only enables the date fields for the custom period" do
      create(:workout, user: user, sport: sport)
      sign_in_user

      get workouts_path
      fields = Nokogiri::HTML(response.body).css("#workout-filters input[type='date']")
      expect(fields.size).to eq(2)
      expect(fields).to all(satisfy { |field| field.key?("disabled") })

      get workouts_path(period: "custom", from: "2026-01-01", to: "2026-02-01")
      fields = Nokogiri::HTML(response.body).css("#workout-filters input[type='date']")
      expect(fields.map { |field| field.key?("disabled") }).to eq([ false, false ])
      expect(fields.map { |field| field["value"] }).to eq(%w[2026-01-01 2026-02-01])
    end

    it "wires the next page into the infinite-scroll sentinel with deterministic newest-first ordering" do
      sign_in_user
      timestamp = Time.zone.parse("2026-08-24 08:00:00")
      workouts = 21.times.map do |index|
        create(:workout, user: user, sport: sport, started_at: timestamp, title: "Workout #{index}")
      end

      get workouts_path
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      items = body.at_css('[data-infinite-scroll-target="items"]')
      expect(items.css(".card").size).to eq(20)
      expect(body.at_css("[data-infinite-scroll-url-value]")["data-infinite-scroll-url-value"]).to include("page=2")
      skeleton = body.at_css('[data-infinite-scroll-target="skeleton"]')
      expect(skeleton.key?("hidden")).to be(true)
      expect(skeleton.at_css(".placeholder-glow .placeholder")).to be_present
      expect(response.body).to include(workouts.last.title)
      expect(response.body).not_to include(workouts.first.title)

      get workouts_path(page: 2)
      expect(response.body).to include(workouts.first.title)
    end

    it "omits the next-page skeleton at the end of the stream" do
      sign_in_user
      create(:workout, user: user, sport: sport, title: "Only workout")

      get workouts_path

      body = response.parsed_body
      expect(body.at_css('[data-infinite-scroll-target="skeleton"]')).to be_nil
      expect(body.at_css("[data-infinite-scroll-url-value]")["data-infinite-scroll-url-value"]).to eq("")
    end

    it "preserves the active filters in the infinite-scroll next-page URL" do
      sign_in_user
      21.times { |index| create(:workout, user: user, sport: sport, title: "Filtered #{index}", distance: (index + 1) * 100) }

      get workouts_path(sports: [ sport.id.to_s ], sort: "distance", direction: "desc")

      url = Nokogiri::HTML(response.body).at_css("[data-infinite-scroll-url-value]")["data-infinite-scroll-url-value"]
      expect(url).to include("page=2", "sort=distance", "direction=desc", "sports%5B%5D=#{sport.id}")
    end

    it "scrolls the table view endlessly through both its desktop rows and its phone list" do
      sign_in_user
      21.times { |index| create(:workout, user: user, sport: sport, title: "Table #{index}") }

      get workouts_path(view: "table")

      body = response.parsed_body
      containers = body.css('[data-infinite-scroll-target="items"]')
      expect(containers.map(&:name)).to eq(%w[tbody ul])
      expect(containers.map { |node| node.element_children.size }).to eq([ 20, 20 ])
      url = body.at_css("[data-infinite-scroll-url-value]")["data-infinite-scroll-url-value"]
      expect(url).to include("page=2", "view=table")
      expect(body.css("noscript").map(&:inner_html).join).to include("pagination")
    end

    it "returns only the owner's workouts" do
      owner = create(:user)
      public_w = create(:workout, user: owner, sport: sport, title: "Public of owner")
      create(:track_segment, workout: public_w)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout: public_w, profile:)
      private_w = create(:workout, user: owner, sport: sport, title: "Private of owner hidden")
      own = create(:workout, user: user, sport: sport, title: "Own private visible")

      sign_in_user
      get workouts_path
      expect(response.body).to include("Own private visible")
      expect(response.body).not_to include("Public of owner")
      expect(response.body).not_to include("Private of owner hidden")
    end

    it "does not expose analysis metrics from another user's timeline card" do
      owner = create(:user)
      public_workout = create(
        :workout,
        user: owner,
        sport: sport,
        title: "Public workout with hidden analysis",
        distance: 9876,
        duration: 367,
        moving_time: 300,
        pause_time: 67
      )
      create(:track_segment, workout: public_workout)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner, settings: PublishingProfile::DEFAULT_SETTINGS.merge("metrics" => [], "mask_start" => false, "mask_finish" => false))
      publish_workout!(user: owner, workout: public_workout, profile:)

      sign_in_user
      get workouts_path

      expect(response.body).not_to include("Public workout with hidden analysis", "9,88 km", "6:07")
    end

    it "uses only the authorized route-image endpoint on owner cards" do
      workout = create(:workout, user:, sport:)
      workout.route_image.attach(io: StringIO.new("png"), filename: "route.png", content_type: "image/png")
      sign_in_user

      get workouts_path

      expect(response.body).to include(workout_route_image_path(workout))
      expect(response.body).not_to include("/rails/active_storage", workout.route_image.blob.key)

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?(workout.title) }
      expect(card.at_css(".placeholder-glow")).to be_nil
    end

    it "reserves the owner card top with a shape-matched skeleton until the route image is attached" do
      workout = create(:workout, user:, sport:)
      sign_in_user

      get workouts_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?(workout.title) }
      skeleton = card.at_css(".ratio.placeholder-glow[role='status']")
      expect(skeleton).to be_present
      expect(skeleton.at_css(".placeholder[aria-hidden='true']")).to be_present
      expect(skeleton.text).to include(I18n.t("workouts.route_image.pending"))
    end

    it "presents list cards like the personal hub: fully clickable, no footer" do
      create(:workout, user:, sport:, title: "Linked ride", started_at: 1.day.ago)

      sign_in_user
      get workouts_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?("Linked ride") }
      expect(card["class"]).to include("position-relative", "workout-card--linked")
      expect(card.at_css("a.stretched-link")).to be_present
      expect(card.at_css(".card-footer")).to be_nil
      expect(card.parent["class"]).to include("col-xxl-3")
    end

    it "keeps smart dates and the compact metric line on list cards" do
      pace_sport = create(:sport, slug: "running_pace", label: "Running pace", pace_speed_display: "pace")
      started = 1.day.ago.in_time_zone(user.time_zone).change(hour: 7, min: 30)
      create(:workout, user:, sport: pace_sport, started_at: started,
                       distance: 12_000, duration: 5100, moving_time: 5000, pause_time: 100,
                       average_pace: 425, ascent: 320)

      sign_in_user
      get workouts_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.at_css("a.stretched-link") }
      expect(card.text).to include("Hier 07:30")
      expect(card.text).to include(I18n.t("units.duration.hours_minutes", hours: 1, minutes: 25))
      expect(card.text).to include(I18n.t("units.pace.per_km"))
      expect(card.text).not_to include(I18n.t("workouts.show.metrics.moving_time"))
    end

    it "shows rowing pace per 500 m, never speed, on the compact card line" do
      rowing = catalog_sport("rowing")
      create(:workout, user:, sport: rowing, distance: 2_000, duration: 480, moving_time: 470,
                       pause_time: 10, average_pace: 235, average_speed: 4.25, max_speed: 4.6)

      sign_in_user
      get workouts_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.at_css("a.stretched-link") }
      expect(card.text).to include(I18n.t("units.pace.per_500m"))
      expect(card.text).not_to include(I18n.t("units.speed.kmh"))
    end

    it "marks the sport tile as an accessible, tooltipped link instead of a printed name" do
      tiled = create(:workout, user:, sport: catalog_sport("running"), title: "Tiled run", started_at: 2.days.ago)
      sign_in_user

      get workouts_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?(tiled.title) }
      tile = card.at_css("a.sport-tile--link")
      expect(tile["aria-label"]).to eq(I18n.t("sports.running"))
      expect(tile["data-bs-title"]).to eq(I18n.t("sports.running"))
      expect(tile["data-controller"]).to eq("tooltip")
      expect(tile["role"]).to be_nil
      expect(card.text).not_to include(I18n.t("sports.running"))
    end

    it "states a shared or scheduled card with an icon-only badge and leaves an unpublished card bare" do
      PublishingProfile.ensure_built_ins_for!(user)
      profile = user.publishing_profiles.find_by!(built_in_key: "public")
      unpublished = create(:workout, user:, sport:, title: "Draft ride")
      published = create(:workout, user:, sport:, title: "Public ride")
      create(:workout_publication, workout: published, publishing_profile: profile)
      scheduled = create(:workout, user:, sport:, title: "Delayed ride")
      create(:workout_publication, :scheduled, workout: scheduled, publishing_profile: profile)
      sign_in_user

      get workouts_path

      cards = Nokogiri::HTML(response.body).css(".card")
      badge_for = ->(title) { cards.find { |node| node.text.include?(title) }.at_css("[data-audience-state]") }

      expect(badge_for.call(unpublished.title)).to be_nil
      expect(badge_for.call(published.title)["data-audience-state"]).to eq("public")
      expect(badge_for.call(published.title)["class"]).to include("bg-success-lt", "allure-badge-icon")
      expect(badge_for.call(published.title).at_css(".ti-broadcast")).to be_present
      expect(badge_for.call(published.title)["data-bs-title"]).to eq(I18n.t("workouts.publication.audience.public"))
      expect(badge_for.call(published.title)["data-tooltip-media-value"]).to be_nil
      expect(badge_for.call(scheduled.title)["data-audience-state"]).to eq("scheduled")
      # Scheduled to the public profile: the public tint, pulsing (DESIGN.md §10.4).
      expect(badge_for.call(scheduled.title)["class"]).to include("bg-success-lt", "allure-badge-pulse")
      expect(badge_for.call(scheduled.title).at_css(".visually-hidden").text).to eq(I18n.t("workouts.scheduled.badge"))
    end

    it "carries the record badge on the owner's list card, lifted above the stretched link" do
      running = catalog_sport("running")
      record_workout = create(:workout, user:, sport: running, title: "Record run", distance: 10_000.0,
                                       duration: 3_700, moving_time: 3_600, pause_time: 100, average_pace: 240)
      plain_workout = create(:workout, user:, sport: running, title: "Plain run", distance: 5_000.0,
                                      duration: 1_900, moving_time: 1_800, pause_time: 100, average_pace: 300)
      sign_in_user

      get workouts_path

      cards = Nokogiri::HTML(response.body).css(".card")
      record_card = cards.find { |node| node.text.include?(record_workout.title) }
      plain_card = cards.find { |node| node.text.include?(plain_workout.title) }

      badge = record_card.at_css(".workout-card__lift .allure-record-badge")
      expect(badge).to be_present
      expect(badge["aria-label"]).to include(I18n.t("records.types.fd"))
      expect(badge["data-controller"]).to eq("tooltip")
      expect(plain_card.at_css(".allure-record-badge")).to be_nil
      expect(plain_card.at_css(".workout-card__lift")).to be_nil
    end

    it "keeps every metric fact whole on the card line, below the smart date" do
      create(:workout, user:, sport: catalog_sport("cycling"), title: "Long ride", distance: 26_500.0,
                       duration: 4_200, moving_time: 4_100, pause_time: 100, average_speed: 7.5, ascent: 350.0)
      sign_in_user

      get workouts_path

      card = Nokogiri::HTML(response.body).css(".card").find { |node| node.text.include?("Long ride") }
      facts = card.css(".allure-table-nums span.text-nowrap").map(&:text)
      expect(facts).to include("26,5 km", I18n.t("units.duration.hours_minutes", hours: 1, minutes: 10), "350 m")
      date_line, fact_line = card.css(".allure-table-nums").first(2)
      expect(date_line.at_css("span.text-nowrap")).to be_nil
      expect(fact_line.text).to include(" · ")
    end
  end

  describe "GET /workouts/:id" do
    it "allows owner to view private" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user
      get workout_path(w)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(w.title)
    end

    it "shows rowing pace per 500 m and power, never speed, in the summary tiles" do
      rowing = catalog_sport("rowing")
      w = create(:workout, user:, sport: rowing, average_pace: 240, average_speed: 4.16,
                            max_speed: 4.5, average_power: 210)
      sign_in_user

      get workout_path(w)

      summary = Nokogiri::HTML(response.body).at_css(".allure-workout-summary")
      expect(summary.text).to include(I18n.t("units.pace.per_500m"))
      expect(summary.text).to include(I18n.t("workouts.show.metrics.average_power"))
      expect(summary.text).not_to include(I18n.t("workouts.show.metrics.average_speed"))
      expect(summary.text).not_to include(I18n.t("workouts.show.metrics.max_speed"))
    end

    it "leads a virtual ride with its power and opens its chart on it" do
      virtual = catalog_sport("cycling_virtual")
      w = create(:workout, user:, sport: virtual, average_speed: 8.0, average_power: 210, ascent: 120)
      create(:track_segment, workout: w, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 0.0, "v" => 2.5, "pw" => 200 },
        { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "ele" => 10.0, "v" => 3.0, "pw" => 220 }
      ])
      sign_in_user

      get workout_path(w)

      page = Nokogiri::HTML(response.body)
      summary = page.at_css(".allure-workout-summary")
      expect(summary.css(".allure-primary-metrics .allure-metric-tile dt").map { |dt| dt.text.strip }).to eq([
        I18n.t("workouts.show.metrics.distance"), I18n.t("workouts.show.metrics.moving_time"),
        I18n.t("workouts.show.metrics.average_power"), I18n.t("workouts.show.metrics.ascent")
      ])
      # The speed keeps its place among the secondary metrics.
      expect(summary.css(".allure-secondary-metrics").text)
        .to include(I18n.t("workouts.show.metrics.average_speed"))

      chart = page.at_css('[data-controller="elevation-chart"]')
      expect(chart["data-elevation-chart-power-led-value"]).to eq("true")
      expect(chart.css("select option").map { |option| option["value"] }).to eq([ "", "power", "speed" ])

      # The analysis tables follow the same rule: the effort column leads with
      # the watts, and each split carries its own average power.
      splits = page.at_css("#workout-laps-splits")
      expect(splits.css("thead th").map { |th| th.text.strip })
        .to include(I18n.t("workouts.show.splits.power"))
      expect(splits.text).to include("210 W")
    end

    it "falls back to the speed on a publication that withholds power" do
      virtual = catalog_sport("cycling_virtual")
      w = create(:workout, user:, sport: virtual, average_speed: 8.0, average_power: 210, ascent: 120)
      create(:track_segment, workout: w, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 0.0, "v" => 2.5, "pw" => 200 },
        { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "ele" => 10.0, "v" => 3.0, "pw" => 220 }
      ])
      profile = create(:publishing_profile, :without_endpoint_masks, user:)
      profile.update!(settings: profile.settings.merge(
        "metrics" => %w[distance duration moving_time ascent average_speed]
      ))
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      summary = Nokogiri::HTML(response.body).at_css(".allure-workout-summary")
      expect(summary.css(".allure-primary-metrics .allure-metric-tile dt").map { |dt| dt.text.strip }).to eq([
        I18n.t("workouts.show.metrics.distance"), I18n.t("workouts.show.metrics.moving_time"),
        I18n.t("workouts.show.metrics.average_speed"), I18n.t("workouts.show.metrics.ascent")
      ])
      expect(summary.text).not_to include(I18n.t("workouts.show.metrics.average_power"))
    end

    it "carries the sport's pace basis on the elevation chart" do
      rowing = catalog_sport("rowing")
      w = create(:workout, user:, sport: rowing, average_pace: 240, average_speed: 4.16)
      create(:track_segment, workout: w, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 0.0, "v" => 4.0 },
        { "t" => 60, "d" => 240.0, "lat" => 45.09, "lon" => 6.43, "ele" => 5.0, "v" => 4.2 }
      ])
      sign_in_user

      get workout_path(w)

      card = response.parsed_body.at_css('[data-controller="elevation-chart"]')
      expect(card["data-elevation-chart-pace-basis-value"]).to eq("500")
      expect(card["data-elevation-chart-pace-basis-label-value"]).to eq(I18n.t("units.pace.per_500m"))
      selector = card.at_css('select[data-elevation-chart-target="secondaryMetric"]')
      expect(selector.css("option").map { |option| option["value"] }).to eq([ "", "pace" ])
    end

    it "uses the interactive map instead of a route image on the workout detail" do
      w = create(:workout, user: user, sport: sport)
      w.route_image.attach(io: StringIO.new("png"), filename: "route.png", content_type: "image/png")
      sign_in_user

      get workout_path(w)

      page = response.parsed_body
      expect(page.css(".allure-workout-route-image")).to be_empty
      expect(response.body).not_to include(workout_route_image_path(w))
      expect(page.at_css("#section-map [data-controller='map']")).to be_present
    end

    it "serves a public workout to a member and 404s a private one" do
      w_public = create(:workout, user: user, sport: sport)
      create(:track_segment, workout: w_public)
      profile = create(:publishing_profile, :without_endpoint_masks, user: user)
      publish_workout!(user:, workout: w_public, profile:)
      w_private = create(:workout, user: user, sport: sport)
      sign_in_user(create(:user))
      get workout_path(w_public)
      expect(response).to have_http_status(:ok)
      get workout_path(w_private)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects an anonymous visitor to sign-in" do
      w = create(:workout, user: user, sport: sport)

      get workout_path(w)

      expect(response).to redirect_to(new_session_path)
    end

    it "returns 404 for invalid ShortUUID" do
      sign_in_user
      get workout_path(id: "invalid")
      expect(response).to have_http_status(:not_found)
    end

    it "does not leak private notes to another viewer" do
      viewer = create(:user)
      w = create(:workout, user: user, sport: sport, notes: "secret notes")
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user:)
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(viewer)
      get workout_path(w)
      expect(response.body).not_to include("secret notes")
    end

    it "shows the owner the recording device from the imported file" do
      w = create(:workout, user:, sport:, source: "Garmin Edge 530")
      sign_in_user

      get workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Garmin Edge 530")
      expect(response.body).to include(I18n.t("workouts.show.device"))
    end

    it "does not leak the recording device to a non-owner when the profile keeps it off" do
      w = create(:workout, user:, sport:, source: "Garmin Edge 530")
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user:)
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Garmin Edge 530")
    end

    it "shares the recording device with a non-owner when the profile enables it" do
      w = create(:workout, user:, sport:, source: "Garmin Edge 530")
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user:,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge("device" => true, "mask_start" => false, "mask_finish" => false))
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Garmin Edge 530")
    end

    it "shows the owner the derived place" do
      w = create(:workout, user:, sport:,
                    places: [ { "name" => "Valmorin", "kind" => "village" }, { "name" => "Rochelune", "kind" => "city" } ])
      sign_in_user

      get workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Valmorin · Rochelune")
    end

    it "never shares the derived place with a non-owner publication" do
      w = create(:workout, user:, sport:,
                    places: [ { "name" => "Valmorin", "kind" => "village" }, { "name" => "Rochelune", "kind" => "city" } ])
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user:)
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Valmorin · Rochelune")
    end

    it "hides analysis metrics when analysis not public for non-owner" do
      w = create(:workout, user: user, sport: sport, distance: 5000, average_speed: 3.0)
      create(:track_segment, workout: w, position: 0, distance: 9876, duration: 367, moving_time: 300, pause_time: 67)
      profile = create(:publishing_profile, :without_endpoint_masks, user:, settings: PublishingProfile::DEFAULT_SETTINGS.merge("metrics" => [], "route" => false, "mask_start" => false, "mask_finish" => false))
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))
      get workout_path(w)
      expect(response.body).not_to include("5,0 km", "9,88 km", "6:07", "Tronçon 1")
      expect(response.body).not_to include(workout_chart_path(w), workout_track_path(w))
    end

    it "drops the basemap from the published map when the profile disables it" do
      w = create(:workout, user: user, sport: sport)
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user:,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge("basemap" => false, "mask_start" => false, "mask_finish" => false))
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response.body).to include('data-map-style-url-value=""', 'data-map-style-url-dark-value=""')
      expect(response.body).to include(workout_track_path(w))

      # The owner's source map keeps its basemap; only the publication loses it.
      sign_in_user
      get workout_path(w)
      expect(response.body).to include(%(data-map-style-url-value="#{Allure::Maps.config.style_url}"))
    end

    it "does not present an unshared route image as pending to a non-owner" do
      w = create(:workout, user: user, sport: sport)
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user: user,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge("route_image" => false, "mask_start" => false, "mask_finish" => false))
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response.body).not_to include(I18n.t("workouts.route_image.title"), I18n.t("workouts.route_image.pending"))
    end

    it "uses the immutable publication sport identity for a non-owner" do
      published_sport = sport
      source_sport = create(:sport, slug: "source_changed", label: "Changed source sport", colour_group: "run", position: 99)
      w = create(:workout, user: user, sport: published_sport)
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user: user)
      publish_workout!(user:, workout: w, profile:)
      w.update!(sport: source_sport)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response.body).to include(published_sport.label)
      expect(response.body).not_to include("Changed source sport")
    end

    it "exposes only authorized representation URLs in workout HTML" do
      w = create(
        :workout,
        user: user,
        sport: sport,
      )
      create(:track_segment, workout: w)
      profile = create(:publishing_profile, :without_endpoint_masks, user:, settings: PublishingProfile::DEFAULT_SETTINGS.merge("mask_start" => false, "mask_finish" => false))
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)
      expect(response.body).to include(workout_chart_path(w))
      expect(response.body).to include(workout_track_path(w))
      expect(response.body).not_to include("6.4074", "45.071")

      sign_in_user
      get workout_path(w)
      expect(response.body).to include(workout_chart_path(w), workout_track_path(w))
    end

    it "shows the owner the sanitized media and the reader's view of a followers publication" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      w = create(:workout, user: user, sport: sport)
      profile = create(:publishing_profile, :followers, user: user)
      publication = create(:workout_publication, workout: w, publishing_profile: profile)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("\x89PNG\r\n\x1A\n".b),
        filename: "sanitized.png",
        content_type: "image/png"
      )
      publication.attach_sanitized_route_image!(blob)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include(publication_route_image_path(publication))
      expect(response.body).not_to include(workout_publication_route_image_path(publication))
      expect(response.body).to include(workout_path(w, as: :publication))

      # The reader's view draws the sanitized track and chart, never the
      # owner's source, and carries no owner section.
      get workout_path(w, as: :publication)
      expect(response.body).to include(workout_track_path(w, as: :publication))
      expect(response.body).to include(I18n.t("workouts.reader_preview.notice"))
      expect(response.parsed_body.at_css("#section-sharing")).to be_nil
      expect(response.parsed_body.at_css("#section-laps")).to be_nil
    end

    it "shows a followers publication's map to an accepted local follower" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      w = create(:workout, user: user, sport: sport)
      create(:track_segment, workout: w)
      owner_actor = Federation::ActorProvisioner.new(user: user).call!
      create(:workout_publication, :with_followers, workout: w, actor: owner_actor)
      follower = create(:user)
      follower_actor = Federation::ActorProvisioner.new(user: follower).call!
      create(:following, :accepted, follower_actor:, followed_actor: owner_actor)
      sign_in_user(follower)

      get workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("section-map", workout_track_path(w))
    end

    it "hides a followers publication from an unrelated account" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      w = create(:workout, user: user, sport: sport)
      create(:workout_publication, :with_followers, workout: w)
      sign_in_user(create(:user))

      get workout_path(w)

      expect(response).to have_http_status(:not_found)
    end

    it "omits the elevation chart when no elevation data exists" do
      w = create(:workout, user: user, sport: sport, min_elevation: nil, max_elevation: nil)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include(workout_track_path(w))
      expect(response.body).not_to include(workout_chart_path(w))
    end

    it "wires the owner's unit system into the elevation chart" do
      user.update!(unit_system: "imperial")
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include('data-elevation-chart-unit-system-value="imperial"')
    end

    it "offers owner-only sensor series with a complete accessible data equivalent" do
      sport.update!(cadence_unit: "rpm", records_power: true)
      w = create(:workout, user: user, sport: sport)
      create(:track_segment, workout: w, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 0.0, "v" => 2.5, "hr" => 140, "cad" => 80, "pw" => 200 },
        { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "ele" => 100.0, "v" => 3.0, "hr" => 150, "cad" => 82, "pw" => 220 }
      ])
      sign_in_user

      get workout_path(w)

      card = response.parsed_body.at_css('[data-controller="elevation-chart"]')
      expect(card["data-elevation-chart-url-value"]).to eq(workout_chart_path(w, version: 2))
      expect(card["data-elevation-chart-toponymy-url-value"]).to eq(workout_toponymy_path(w))
      selector = card.at_css('select[data-elevation-chart-target="secondaryMetric"]')
      expect(selector["data-action"]).to eq("change->elevation-chart#secondaryMetricChanged")
      expect(selector.css("option").map { |option| option["value"] }).to eq([ "", *%w[speed heart_rate cadence power] ])

      headers = card.css("table thead th").map { |header| header.text.strip }
      expect(headers).to eq([
        I18n.t("workouts.show.chart.distance"), I18n.t("workouts.show.chart.elapsed_time"),
        I18n.t("workouts.show.chart.series.elevation"), I18n.t("workouts.show.chart.series.speed"),
        I18n.t("workouts.show.chart.series.heart_rate"), I18n.t("workouts.show.chart.series.cadence"),
        I18n.t("workouts.show.chart.series.power")
      ])
      expect(card.text).to include("0 m", "9,0 km/h", "140 bpm", "80 rpm", "200 W")
    end

    it "keeps detailed sensor controls out of a published non-owner page" do
      w = create(:workout, user: user, sport: sport)
      create(:track_segment, workout: w, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 100.0, "hr" => 197 },
        { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "ele" => 112.0, "hr" => 199 }
      ])
      profile = create(:publishing_profile, :without_endpoint_masks, user: user)
      publish_workout!(user:, workout: w, profile:)
      sign_in_user(create(:user))

      get workout_path(w)

      card = response.parsed_body.at_css('[data-controller="elevation-chart"]')
      expect(card["data-elevation-chart-url-value"]).to eq(workout_chart_path(w))
      expect(card["data-elevation-chart-toponymy-url-value"]).to be_nil
      expect(card.at_css('[data-elevation-chart-target="secondaryMetric"]')).to be_nil
      expect(card.text).not_to include("197", "199", I18n.t("workouts.show.chart.series.heart_rate"))
    end

    it "renders an owner sensor profile when elevation is unavailable" do
      w = create(:workout, user: user, sport: sport, min_elevation: nil, max_elevation: nil)
      create(:track_segment, workout: w, min_elevation: nil, max_elevation: nil, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "hr" => 140 },
        { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "hr" => 150 }
      ])
      sign_in_user

      get workout_path(w)

      expect(response.body).to include(workout_chart_path(w, version: 2))
      expect(response.body).to include('value="heart_rate"')
      expect(response.body).not_to include(I18n.t("workouts.show.chart.unavailable"))
    end

    it "wires both basemap styles into the map so a theme toggle needs no round trip" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include(
        %(data-map-style-url-value="#{Allure::Maps.config.style_url}"),
        %(data-map-style-url-dark-value="#{Allure::Maps.config.dark_style_url}"),
        "allure:theme-changed@window-&gt;map#themeChanged"
      )
    end

    it "draws a virtual activity on its world's own map image" do
      point = RGeo::Geographic.spherical_factory(srid: 4326).point(166.95251, -11.63555)
      w = create(:workout, user:, sport: catalog_sport("cycling_virtual"), start_point: point,
                            bounds: [ -11.63555, 166.95251, -11.63555, 166.95251 ])
      # The world images are not committed (PLAN_VIRTUAL.md §2.1); the lookup
      # itself is covered in platforms_spec.
      allow(Allure::Virtual::Platforms).to receive(:basemap_at).and_return(
        Allure::Virtual::Basemap.new(
          image: "virtual_worlds/zwift/watopia-f4991742.webp",
          bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ],
          background: "#0884e2"
        )
      )
      sign_in_user

      get workout_path(w)

      map = Nokogiri::HTML(response.body).at_css("[data-controller~='map']")
      world = JSON.parse(map["data-map-virtual-basemap-value"])
      expect(world).to include(
        "background" => "#0884e2",
        "darkBackground" => "#032a48",
        "attribution" => "© Zwift"
      )
      expect(world["image"]).to start_with("/virtual_worlds/zwift/watopia")
      expect(world["coordinates"].length).to eq(4)
    end

    it "keeps the ordinary basemap when the world image is not generated" do
      point = RGeo::Geographic.spherical_factory(srid: 4326).point(166.95251, -11.63555)
      w = create(:workout, user:, sport: catalog_sport("cycling_virtual"), start_point: point,
                            bounds: [ -11.63555, 166.95251, -11.63555, 166.95251 ])
      sign_in_user

      get workout_path(w)

      expect(response.body).not_to include("data-map-virtual-basemap-value")
    end

    it "keeps the ordinary basemap for a real ride where a world shares the city" do
      # Zwift's London rectangle covers real London.
      point = RGeo::Geographic.spherical_factory(srid: 4326).point(-0.11655, 51.49815)
      w = create(:workout, user:, sport: catalog_sport("cycling_road"), start_point: point,
                            bounds: [ 51.49815, -0.11655, 51.49815, -0.11655 ])
      sign_in_user

      get workout_path(w)

      expect(response.body).not_to include("data-map-virtual-basemap-value")
    end

    it "keeps the ordinary basemap for a virtual world the catalogue does not know" do
      point = RGeo::Geographic.spherical_factory(srid: 4326).point(0, 0)
      w = create(:workout, user:, sport: catalog_sport("cycling_virtual"), start_point: point,
                            bounds: [ 0, 0, 0, 0 ])
      sign_in_user

      get workout_path(w)

      expect(response.body).not_to include("data-map-virtual-basemap-value")
      expect(response.body).to include(%(data-map-style-url-value="#{Allure::Maps.config.style_url}"))
    end

    it "paints the account's forced basemap on the map, whatever the page theme" do
      user.update!(theme: "dark", route_image_theme: "light")
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      canvas = Nokogiri::HTML(response.body).at_css('[data-map-target="canvas"]')
      expect(canvas["data-bs-theme"]).to eq("light")
      expect(response.body).to include('data-map-basemap-theme-value="light"')
    end

    it "lets the basemap follow the page theme by default" do
      user.update!(theme: "dark")
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      canvas = Nokogiri::HTML(response.body).at_css('[data-map-target="canvas"]')
      expect(canvas["data-bs-theme"]).to eq("dark")
      expect(response.body).to include('data-map-basemap-theme-value="auto"')
    end

    it "wires the owner's unit system into the map scale" do
      user.update!(unit_system: "imperial")
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include('data-map-unit-system-value="imperial"')
    end

    it "offers the colour-by metrics, hidden until the controller finds more than one" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include(
        'data-map-target="metric"',
        # Literal in the template rather than interpolated, so it is not escaped
        # the way the card's own data-action is.
        "change->map#metricChanged",
        %(<option value="elevation">#{I18n.t("maps.colour_by.elevation")}</option>),
        %(<option value="speed">#{I18n.t("maps.colour_by.speed")}</option>)
      )
    end

    it "subscribes both the map and the chart to the hover channel" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      expect(response.body).to include(
        # The map builds its action list in Ruby, so it arrives escaped; the
        # chart's is a literal in the template and does not.
        "allure:track-hover@window-&gt;map#trackHover",
        "allure:track-hover@window->elevation-chart#trackHover"
      )
    end

    it "localizes the map controls through MapLibre's own locale keys" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get workout_path(w)

      locale = JSON.parse(CGI.unescapeHTML(response.body[/data-map-locale-value="([^"]*)"/, 1]))
      expect(locale).to include(
        "NavigationControl.ZoomIn" => I18n.t("maps.controls.zoom_in"),
        "FullscreenControl.Enter" => I18n.t("maps.controls.enter_fullscreen"),
        # The scale bar and the elevation chart must abbreviate units identically.
        "ScaleControl.Kilometers" => I18n.t("units.symbols.kilometre")
      )
    end

    describe "data anomalies" do
      let(:anomalies) do
        {
          "findings" => [
            { "kind" => "gps_rejected", "start_distance" => 100.0, "end_distance" => 104.0, "start_time" => 20,
              "end_time" => 24, "detail" => { "value" => 1, "count" => 1 },
              "coordinates" => [ [ 6.0005, 45.0001 ] ], "path" => [ [ 6.0, 45.0 ], [ 6.0005, 45.0001 ], [ 6.0, 45.0002 ] ] },
            { "kind" => "hr_frozen", "start_distance" => 500.0, "end_distance" => 700.0, "start_time" => 120,
              "end_time" => 160, "detail" => { "value" => 163, "bpm" => 163, "frozen" => 23, "missing" => 24 } }
          ],
          "counts" => { "gps_rejected" => 1, "hr_frozen" => 1 }
        }
      end

      let(:elevation_mismatch_anomalies) do
        {
          "findings" => [
            { "kind" => "elevation_mismatch", "tier" => "major", "start_distance" => 27_949.6, "end_distance" => 28_331.7,
              "start_time" => 6118, "end_time" => 6186,
              "detail" => { "value" => 18.7, "metres" => 18.7, "peak" => 25.7, "spread" => 8.1,
                            "first_distance" => 27_443.4, "first_time" => 5775, "count" => 12 } }
          ],
          "counts" => { "elevation_mismatch" => 1 },
          "impact" => { "ascent" => { "recorded" => 194, "gap" => 25.7,
                                      "start_distance" => 27_949.6, "end_distance" => 28_331.7 } }
        }
      end

      it "shows the owner the data quality tab and the dashes on the map and the chart, without a header badge" do
        w = create(:workout, user: user, sport: sport, data_anomalies: anomalies)
        create(:track_segment, workout: w)
        sign_in_user

        get workout_path(w)

        page = response.parsed_body
        expect(page.at_css(".page-header a.badge.bg-warning-lt")).to be_nil
        expect(page.at_css(".allure-anomaly-note")).to be_nil
        expect(page.at_css("#workout-laps-tab-anomalies").text).to include("2")
        expect(page.at_css("#workout-laps-anomalies").text)
          .to include(I18n.t("workouts.anomalies.kinds.hr_frozen"), I18n.t("workouts.anomalies.kinds.gps_rejected"))
        map = JSON.parse(page.at_css("[data-map-anomalies-value]")["data-map-anomalies-value"])
        expect(map).to contain_exactly(include("coordinates" => [ [ 6.0005, 45.0001 ] ]))
        chart = JSON.parse(page.at_css("[data-elevation-chart-anomalies-value]")["data-elevation-chart-anomalies-value"])
        expect(chart.map { |entry| entry["family"] }).to contain_exactly("gps", "heart_rate")
        expect(chart.map { |entry| entry["tier"] }).to all(eq("minor"))
      end

      it "annotates a figure an anomaly makes wrong with its plausible value" do
        speed_anomalies = {
          "findings" => [
            { "kind" => "gps_jump", "tier" => "major", "start_distance" => 100.0, "end_distance" => 180.0,
              "start_time" => 20, "end_time" => 21, "detail" => { "value" => 288.0, "speed" => 288.0, "metres" => 80, "excess" => 78 } }
          ],
          "counts" => { "gps_jump" => 1 },
          "impact" => { "max_speed" => { "recorded" => 20.0, "plausible" => 3.0, "basis" => "track",
                                         "start_distance" => 90.0, "end_distance" => 190.0 } }
        }
        w = create(:workout, user: user, sport: sport, max_speed: 20.0, data_anomalies: speed_anomalies,
                             contested_metrics: %w[best_pace max_speed])
        create(:track_segment, workout: w)
        sign_in_user

        get workout_path(w)

        page = response.parsed_body
        note = page.at_css("dt .allure-anomaly-note")
        # The sentence lives in the mark's tooltip beside the metric's label,
        # and the tile carries no other control: the analysis tab is its text
        # and its stretch (DESIGN.md §15.5).
        expect(note.parent.name).to eq("dt")
        expect(note["data-bs-title"]).to include(I18n.t("workouts.anomalies.notes.excluded"))
        expect(note["aria-label"]).to eq(note["data-bs-title"])
        expect(note.text.strip).to be_empty
        expect(page.at_css(".allure-anomaly-note button, .allure-anomaly-note a")).to be_nil
        expect(page.at_css("#workout-laps-anomalies").text).to include(I18n.t("workouts.anomalies.impact.title"))
        chart = JSON.parse(page.at_css("[data-elevation-chart-anomalies-value]")["data-elevation-chart-anomalies-value"])
        expect(chart.first["tier"]).to eq("major")
      end

      it "never shows them to another reader of the published workout" do
        w = create(:workout, user: user, sport: sport, data_anomalies: anomalies)
        create(:track_segment, workout: w)
        create(:workout_publication, workout: w, publishing_profile: public_publishing_profile_for(user), status: "active")
        sign_in_as(create(:user))

        get workout_path(w)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("data-map-anomalies-value", "data-elevation-chart-anomalies-value",
                                             I18n.t("workouts.anomalies.kinds.hr_frozen"))
      end

      it "offers the terrain profile where the recorded one disagrees with itself" do
        w = create(:workout, user: user, sport: sport, data_anomalies: elevation_mismatch_anomalies,
                             contested_metrics: %w[ascent])
        create(:track_segment, workout: w)
        sign_in_user

        with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
          user.update!(elevation_enrichment_enabled: true)

          get workout_path(w)

          page = response.parsed_body
          tab = page.at_css("#workout-laps-anomalies").text
          expect(tab).to include(I18n.t("workouts.anomalies.kinds.elevation_mismatch"),
                                 I18n.t("workouts.anomalies.notes.excluded_metric"))
          expect(tab).to include(I18n.t("workouts.anomalies.elevation_hint"))
          expect(page.at_css("#workout-laps-anomalies form[action='#{workout_elevation_source_path(w)}']")).to be_present
        end
      end

      it "keeps the elevation hint to accounts and instances that can use it" do
        w = create(:workout, user: user, sport: sport, data_anomalies: elevation_mismatch_anomalies,
                             contested_metrics: %w[ascent])
        create(:track_segment, workout: w)
        sign_in_user

        with_env("ELEVATION_BASE_URL" => nil) do
          user.update!(elevation_enrichment_enabled: true)

          get workout_path(w)

          expect(response.body).not_to include(I18n.t("workouts.anomalies.elevation_hint"))
        end
      end

      it "renders nothing for a clean recording" do
        w = create(:workout, user: user, sport: sport)
        create(:track_segment, workout: w)
        sign_in_user

        get workout_path(w)

        expect(response.body).not_to include("workout-laps-anomalies", "data-map-anomalies-value")
      end
    end

    describe "laps and splits sections" do
      it "renders the merged analysis card with segments first and every non-empty tab" do
        w = create(:workout, user: user, sport: sport)
        create(:track_segment, workout: w)
        create(:lap, workout: w, number: 1)
        create(:lap, workout: w, number: 2)
        create(:detected_lap, :loop, workout: w, start_distance: 0.0, end_distance: 200.0)
        create(:detected_lap, :climb, workout: w, number: 1, start_distance: 400.0, end_distance: 800.0)
        create(:detected_lap, :descent, workout: w, number: 1, start_distance: 900.0, end_distance: 1_200.0)
        create(:detected_lap, :stop, workout: w, number: 1, start_distance: 300.0, end_distance: 300.0)
        segment = create(:segment, user: user, sport: sport, name: "Col du Test")
        create(:segment_effort, segment: segment, workout: w, user: user, sport: sport)
        sign_in_user

        get workout_path(w)

        expect(response.body).to include(I18n.t("workouts.show.laps.title"))
        expect(response.body).to include(I18n.t("workouts.show.laps.tabs.segments"))
        expect(response.body).to include(I18n.t("workouts.show.laps.tabs.detected"))
        expect(response.body).to include(I18n.t("workouts.show.laps.tabs.climbs"))
        expect(response.body).to include(I18n.t("workouts.show.laps.tabs.stops"))
        expect(response.body).to include(I18n.t("workouts.show.laps.tabs.recorded"))
        expect(response.body).to include(I18n.t("workouts.show.laps.tabs.splits"))
        expect(response.body).to include(I18n.t("workouts.show.laps.sources.loop"))
        expect(response.body).to include(I18n.t("workouts.show.laps.grade"))
        expect(response.parsed_body.at_css("#section-laps")).to be_present
        expect(response.parsed_body.at_css("#section-segments")).to be_nil

        segments_tab = response.parsed_body.at_css("#workout-laps-tab-segments")
        expect(segments_tab["aria-selected"]).to eq("true")
        effort_row = response.parsed_body.at_css("#workout-laps-segments tbody tr[data-analysis-range]")
        expect(effort_row["tabindex"]).to eq("0")
        expect(effort_row["data-start-distance"]).to eq("0.0")
        expect(effort_row["data-end-distance"]).to eq("250.0")

        stops_pane = response.parsed_body.at_css("#workout-laps-stops")
        expect(stops_pane["data-boundaries"]).to be_nil
        expect(stops_pane["data-markers"]).to include('"glyph":"stop"')
        expect(stops_pane["data-analysis-steps"]).to include('"source":"stop"', '"icon":"player-pause"')
        stop_row = response.parsed_body.at_css("#workout-laps-stops tbody tr[data-analysis-range]")
        expect(stop_row["data-analysis-source"]).to eq("stop")
        expect(stop_row["data-analysis-label"]).to eq("1:00")

        descents_pane = response.parsed_body.at_css("#workout-laps-descents")
        expect(descents_pane["data-markers"]).to include('"distance":900.0', '"glyph":"mountain"')
        expect(descents_pane["data-analysis-steps"]).to include('"source":"descent"', '"icon":"mountain"')

        row = response.parsed_body.at_css("#workout-laps-detected tbody tr[data-analysis-range]")
        expect(row["tabindex"]).to eq("0")
        expect(row["data-start-distance"]).to eq("0.0")
        expect(row["data-end-distance"]).to eq("200.0")
      end

      it "keeps the RP badge gold and sets the board rank medal beside it" do
        w = create(:workout, user: user, sport: sport)
        segment = create(:segment, user: user, sport: sport, name: "Col du Test", visibility: "public")
        create(:workout_publication, workout: w, publishing_profile: public_publishing_profile_for(user), status: "active")
        create(:segment_effort, segment:, workout: w, user:, sport:, elapsed_time: 120, moving_time: 100,
                                personal_best: true)
        sign_in_user

        get workout_path(w)

        badge = response.parsed_body.at_css("#workout-laps-segments .allure-record-badge")
        expect(badge["class"]).to include("badge", "bg-secondary-lt")
        expect(badge.at_css("i.ti-trophy.allure-medal--gold")).to be_present
        expect(badge["data-bs-title"]).to eq(I18n.t("medals.record", record: "Col du Test"))
        rank = response.parsed_body.at_css("#workout-laps-segments .allure-segment-effort-rank")
        expect(rank.at_css(".allure-medal--gold")).to be_present
        expect(rank.text.squish).to include(I18n.t("medals.rank", rank: 1), "/ 1")
      end

      it "shows the silver rank medal when another athlete is faster, never a silver trophy" do
        w = create(:workout, user: user, sport: sport)
        segment = create(:segment, user: user, sport: sport, name: "Col du Test", visibility: "public")
        create(:workout_publication, workout: w, publishing_profile: public_publishing_profile_for(user), status: "active")
        create(:segment_effort, segment:, workout: w, user:, sport:, elapsed_time: 120, moving_time: 100,
                                personal_best: true)
        rival = create(:user)
        rival_workout = create(:workout, user: rival, sport: sport)
        create(:workout_publication, workout: rival_workout, publishing_profile: public_publishing_profile_for(rival), status: "active")
        create(:segment_effort, segment:, workout: rival_workout, user: rival, sport:, elapsed_time: 100, moving_time: 90)
        sign_in_user

        get workout_path(w)

        badge = response.parsed_body.at_css("#workout-laps-segments .allure-record-badge")
        expect(badge.at_css("i.ti-trophy.allure-medal--gold")).to be_present
        expect(badge["data-bs-title"]).not_to include(I18n.t("medals.second"))
        rank = response.parsed_body.at_css("#workout-laps-segments .allure-segment-effort-rank")
        expect(rank.at_css(".allure-rank-numeral")["data-bs-title"]).to eq(I18n.t("medals.second"))
        expect(rank.text.squish).to include("/ 2")
      end

      it "keeps the gold RP badge alone when the board does not rank the effort" do
        w = create(:workout, user: user, sport: sport)
        segment = create(:segment, user: user, sport: sport, name: "Ma boucle privée", visibility: "private")
        create(:segment_effort, segment:, workout: w, user:, sport:, elapsed_time: 120, moving_time: 100,
                                personal_best: true)
        sign_in_user

        get workout_path(w)

        badge = response.parsed_body.at_css("#workout-laps-segments .allure-record-badge")
        expect(badge).to be_present
        expect(badge.at_css("i.ti-trophy.allure-medal--gold")).to be_present
        expect(badge["data-bs-title"]).to include("Ma boucle privée")
        expect(response.parsed_body.at_css("#workout-laps-segments .allure-rank")).to be_nil
      end

      it "marks the owner's second best time on a segment with the silver pill, without a board rank" do
        segment = create(:segment, user: user, sport: sport, name: "Col du Test", visibility: "public")
        best = create(:workout, user: user, sport: sport, started_at: 3.days.ago)
        create(:segment_effort, segment:, workout: best, user:, sport:, elapsed_time: 100, personal_best: true)
        w = create(:workout, user: user, sport: sport, started_at: 1.day.ago)
        create(:workout_publication, workout: w, publishing_profile: public_publishing_profile_for(user), status: "active")
        create(:segment_effort, segment:, workout: w, user:, sport:, elapsed_time: 120)
        sign_in_user

        get workout_path(w)

        badge = response.parsed_body.at_css("#workout-laps-segments .allure-record-badge")
        expect(badge.at_css("i.ti-trophy.allure-medal--silver")).to be_present
        expect(badge.text.squish).to eq(I18n.t("medals.personal_place_short.second"))
        expect(badge["data-bs-title"]).to eq(I18n.t("medals.personal_place.second", record: "Col du Test"))
        expect(response.parsed_body.at_css("#workout-laps-segments .allure-segment-effort-rank")).to be_nil
      end

      it "shows each segment effort against the owner's personal best and keeps the deviation for wide cards" do
        segment = create(:segment, user: user, sport: sport, name: "Col du Test", visibility: "public")
        best = create(:workout, user: user, sport: sport, started_at: 3.days.ago)
        create(:segment_effort, segment:, workout: best, user:, sport:, elapsed_time: 100, personal_best: true)
        w = create(:workout, user: user, sport: sport, started_at: 1.day.ago)
        create(:segment_effort, segment:, workout: w, user:, sport:, elapsed_time: 172)
        sign_in_user

        get workout_path(w)

        pane = response.parsed_body.at_css("#workout-laps-segments")
        headers = pane.css("thead th")
        expect(headers[4].text.squish).to eq(I18n.t("workouts.show.segment_efforts.personal_best_gap"))
        expect(pane.css("tbody tr td")[4].text.squish).to eq("+1:12")
        expect(pane.at_css(".allure-analysis-list").text).to include("+1:12")
        deviation = headers.find { |th| th.text.squish == I18n.t("workouts.show.segment_efforts.deviation") }
        expect(deviation["class"]).to include("allure-col-extra")

        get workout_path(best)

        margin = response.parsed_body.css("#workout-laps-segments tbody tr td")[4].at_css(".text-success")
        expect(margin.text.squish).to eq("−1:12")
      end

      it "never shows a personal place to another reader of the published workout" do
        segment = create(:segment, user: user, sport: sport, name: "Col du Test", visibility: "public")
        w = create(:workout, user: user, sport: sport)
        create(:workout_publication, workout: w, publishing_profile: public_publishing_profile_for(user), status: "active")
        create(:segment_effort, segment:, workout: w, user:, sport:, elapsed_time: 120, personal_best: true)
        sign_in_as(create(:user))

        get workout_path(w)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("allure-medal--silver", "allure-medal--bronze")
        expect(response.parsed_body.at_css("#workout-laps-segments")).to be_nil
      end

      it "renders only the tabs that have data" do
        w = create(:workout, user: user, sport: sport)
        create(:track_segment, workout: w)
        sign_in_user

        get workout_path(w)

        expect(response.body).to include(I18n.t("workouts.show.laps.title"))
        expect(response.body).to include(I18n.t("workouts.show.splits.title"))
        expect(response.body).to include(I18n.t("workouts.show.splits.partial"))
        expect(response.body).not_to include(I18n.t("workouts.show.laps.tabs.detected"))
      end

      it "hides the whole card from a non-owner viewer" do
        w = create(:workout, user: user, sport: sport)
        create(:track_segment, workout: w)
        create(:lap, workout: w, number: 1)
        profile = create(:publishing_profile, :without_endpoint_masks, user: user)
        publish_workout!(user:, workout: w, profile:)
        sign_in_user(create(:user))

        get workout_path(w)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(I18n.t("workouts.show.laps.title"))
        expect(response.body).not_to include(I18n.t("workouts.show.splits.title"))
      end
    end
  end

  describe "GET /workouts/new" do
    it "redirects the retired single-file import to the import page, query string included" do
      sign_in_user

      get "/workouts/new", params: { locale: "en" }

      expect(response).to redirect_to("/workout_imports/new?locale=en")
    end
  end

  describe "PATCH /workouts/:id" do
    it "does not update legacy visibility through the edit form" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user
      patch workout_path(w), params: { workout: { workout_visibility: "private" } }
      expect(response).to redirect_to(workout_path(w))
      w.reload
      expect(w.active_publications.first).to be_nil
    end

    it "changes the sport and re-analyses the workout" do
      cycling = catalog_sport("cycling")
      running = catalog_sport("running")
      w = imported_workout(sport: cycling)
      sign_in_user

      patch workout_path(w), params: { workout: { sport_id: running.id } }

      expect(response).to redirect_to(workout_path(w))
      expect(w.reload.sport).to eq(running)
      expect(w.grade_adjusted_pace).to be_present
    end

    it "rejects an unknown sport selection" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      patch workout_path(w), params: { workout: { sport_id: 0 } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("workouts.import.errors.missing_sport"))
    end

    it "refuses a sport change without the original file" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      patch workout_path(w), params: { workout: { sport_id: catalog_sport("running").id } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.update.sport_change.missing_original_file")))
      expect(w.reload.sport).to eq(sport)
    end

    it "rejects non-owner" do
      other = create(:user)
      w = create(:workout, user: user, sport: sport)
      sign_in_user(other)
      patch workout_path(w), params: { workout: { title: "hacked" } }
      expect(response).to have_http_status(:not_found)
    end

    it "toggles the commute flag" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      patch workout_path(w), params: { workout: { commute: "1" } }
      expect(response).to redirect_to(workout_path(w))
      expect(w.reload).to be_commute

      patch workout_path(w), params: { workout: { commute: "0" } }
      expect(w.reload).not_to be_commute
    end
  end

  describe "GET /workouts/:id/edit" do
    it "does not size the title field from its maximum length" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get edit_workout_path(w)

      title_field = Nokogiri::HTML(response.body).at_css("#workout_title")
      expect(title_field["maxlength"]).to eq("255")
      expect(title_field["size"]).to be_nil
    end

    it "does not expose legacy visibility controls" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get edit_workout_path(w)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("visibility#capChildren", "workout_workout_visibility")
      expect(response.body).to include("<title>Modifier l&#39;activité · Allure</title>")
      expect(response.body).not_to include("l&amp;#39;activité")
    end

    it "offers the sport selector with its change hint" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get edit_workout_path(w)

      expect(response.body).to include("workout[sport_id]", ERB::Util.html_escape(I18n.t("workouts.form.sport_change_hint")))
    end

    it "renders the commute checkbox" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user

      get edit_workout_path(w)

      expect(response.body).to include("workout[commute]", I18n.t("workouts.form.commute"))
    end
  end

  describe "DELETE /workouts/:id" do
    it "deletes owned workout" do
      w = create(:workout, user: user, sport: sport)
      sign_in_user
      expect do
        delete workout_path(w)
      end.to change(Workout, :count).by(-1)
      expect(response).to redirect_to(workouts_path)
    end
  end

  describe "GET /workouts/:id/original_file" do
    it "redirects an anonymous visitor to sign-in" do
      w = create(:workout, user: user, sport: sport)
      w.original_file.attach(io: StringIO.new("gpx"), filename: "a.gpx", content_type: "application/gpx+xml")
      get workout_original_file_path(w)
      expect(response).to redirect_to(new_session_path)
    end

    it "allows owner to download" do
      w = create(:workout, user: user, sport: sport)
      w.original_file.attach(io: StringIO.new("<gpx></gpx>"), filename: "a.gpx", content_type: "application/gpx+xml")
      sign_in_user
      get workout_original_file_path(w)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("private, no-store")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "serves a FIT source with its own content type and filename" do
      bytes = build_fit(points: simple_fit_points)
      w = create(:workout, :fit, user: user, sport: sport)
      w.original_file.attach(io: StringIO.new(bytes.b), filename: "ride.fit",
                             content_type: "application/vnd.ant.fit")
      sign_in_user

      get workout_original_file_path(w)

      expect(response.media_type).to eq("application/vnd.ant.fit")
      expect(response.headers["Content-Disposition"]).to include("ride.fit")
      expect(response.body.b).to eq(bytes.b)
    end

    it "returns 404 for another user" do
      w = create(:workout, user: user, sport: sport)
      w.original_file.attach(io: StringIO.new("<gpx></gpx>"), filename: "a.gpx", content_type: "application/gpx+xml")
      other = create(:user)
      sign_in_user(other)
      get workout_original_file_path(w)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "equipment selection" do
    it "syncs gear on update, clearing when none checked" do
      gear = create(:equipment, user:)
      other_gear = create(:equipment, user:)
      workout = create(:workout, user:, sport:)
      Equipments::Totals.sync(workout, [ gear.id, other_gear.id ])
      sign_in_user

      patch workout_path(workout), params: { workout: { title: "Kept", equipment_ids: [ gear.id.to_s ] } }

      expect(response).to redirect_to(workout_path(workout))
      expect(workout.reload.equipment_ids).to eq([ gear.id ])
      expect(other_gear.reload.total_workouts).to eq(0)

      patch workout_path(workout), params: { workout: { title: "Kept", equipment_ids: [ "" ] } }

      expect(workout.reload.equipment_ids).to be_empty
    end

    it "checks already-attached gear on edit" do
      gear = create(:equipment, user:)
      workout = create(:workout, user:, sport:)
      Equipments::Totals.sync(workout, [ gear.id ])
      sign_in_user

      get edit_workout_path(workout)

      expect(response.body).to include("checked=\"checked\"")
    end
  end

  describe "GET /workouts/:id best efforts" do
    def create_held_effort(workout, sport, distance_key: "km5", duration_seconds: 1_500)
      create(:best_effort, workout:, distance_key:, distance_meters: 5_000,
                           duration_seconds:, start_offset_meters: 0.0, end_offset_meters: 5_000.0)
      create(:effort_record, user:, sport:, workout:,
                             distance_key:, distance_meters: 5_000, duration_seconds:)
    end

    it "shows the best-efforts tab with the trophy and hover range for the record holder" do
      running = catalog_sport("running")
      workout = create(:workout, user:, sport: running, distance: 5_000.0)
      create_held_effort(workout, running)
      sign_in_user

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("workouts.show.laps.tabs.best_efforts"))
      expect(response.body).to include(I18n.t("records.distances.km5"), "25:00")
      expect(response.body).to include(I18n.t("workouts.show.records.badge_short"))
      expect(response.body).to include(I18n.t("medals.record", record: I18n.t("records.distances.km5")))
      expect(response.body).to include("data-analysis-range", "data-start-distance=\"0.0\"", "data-end-distance=\"5000.0\"")
    end

    it "renders the rowing effort pace over 500 m" do
      rowing = catalog_sport("rowing")
      workout = create(:workout, user:, sport: rowing, distance: 2_000.0)
      create(:best_effort, workout:, distance_key: "km2", distance_meters: 2_000,
                           duration_seconds: 400, start_offset_meters: 0.0, end_offset_meters: 2_000.0)
      create(:effort_record, user:, sport: rowing, workout:,
                             distance_key: "km2", distance_meters: 2_000, duration_seconds: 400)
      sign_in_user

      get workout_path(workout)

      expect(response.body).to include(I18n.t("records.distances.km2"), "6:40")
      expect(response.body).to include("1:40 /500m")
    end

    it "lists a best effort without a trophy when it is not the record" do
      running = catalog_sport("running")
      workout = create(:workout, user:, sport: running, distance: 5_000.0)
      create(:best_effort, workout:, distance_key: "km5", distance_meters: 5_000,
                           duration_seconds: 1_600, start_offset_meters: 0.0, end_offset_meters: 5_000.0)
      Record.where(user:, workout:).delete_all
      sign_in_user

      get workout_path(workout)

      expect(response.body).to include(I18n.t("records.distances.km5"))
      expect(response.body).not_to include(I18n.t("medals.record", record: I18n.t("records.distances.km5")))
      expect(response.parsed_body.at_css(".allure-workout-header .allure-record-badge")).to be_nil
    end

    it "removes the trophy from the previous holder when another workout sets the record" do
      running = catalog_sport("running")
      first = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      create_held_effort(first, running)
      sign_in_user

      get workout_path(first)
      expect(response.body).to include(I18n.t("medals.record", record: I18n.t("records.distances.km5")))

      second = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:best_effort, workout: second, distance_key: "km5", distance_meters: 5_000,
                           duration_seconds: 1_400, start_offset_meters: 0.0, end_offset_meters: 5_000.0)
      Records::RecomputeService.new(user:, sport: running).call

      get workout_path(first)
      expect(response.body).not_to include(I18n.t("medals.record", record: I18n.t("records.distances.km5")))

      get workout_path(second)
      expect(response.body).to include(I18n.t("medals.record", record: I18n.t("records.distances.km5")))
      expect(response.body).to include(I18n.t("workouts.show.records.badge_short"))
    end

    it "marks the owner's second best time with the silver trophy, never as a record" do
      running = catalog_sport("running")
      first = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      create(:best_effort, workout: first, distance_key: "km5", distance_meters: 5_000,
                           duration_seconds: 1_500, start_offset_meters: 0.0, end_offset_meters: 5_000.0)
      second = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:best_effort, workout: second, distance_key: "km5", distance_meters: 5_000,
                           duration_seconds: 1_400, start_offset_meters: 0.0, end_offset_meters: 5_000.0)
      Records::RecomputeService.new(user:, sport: running).call
      sign_in_user

      get workout_path(first)

      pane = response.parsed_body.at_css("#workout-laps-best_efforts")
      expect(pane.at_css("i.ti-trophy.allure-medal--silver")).to be_present
      expect(pane.at_css("i.ti-trophy.allure-medal--gold")).to be_nil
      expect(response.body).to include(I18n.t("medals.personal_place.second", record: I18n.t("records.distances.km5")))
    end

    it "hides the best-efforts tab when the workout has none" do
      sign_in_user
      workout = create(:workout, user:, sport:)

      get workout_path(workout)

      # Scope to the tab list: the release-notes dialog legitimately contains
      # the phrase "Meilleurs efforts" on every signed-in page.
      expect(response.body).not_to include(%(id="workout-laps-tab-best_efforts"))
    end
  end

  describe "GET /workouts/:id record trophies" do
    it "combines classic records and best-effort distances in the header badge" do
      running = catalog_sport("running")
      workout = create(:workout, user:, sport: running, distance: 5_000.0)
      create(:best_effort, workout:, distance_key: "km5", distance_meters: 5_000,
                           duration_seconds: 1_500, start_offset_meters: 0.0, end_offset_meters: 5_000.0)
      create(:effort_record, user:, sport: running, workout:,
                             distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_500)
      sign_in_user

      get workout_path(workout)

      prefix = Regexp.escape(I18n.t("medals.records", records: "", count: 2))
      expect(response.body).to match(/#{prefix}.*#{Regexp.escape(I18n.t("records.types.fd"))}.*#{Regexp.escape(I18n.t("records.distances.km5"))}/)
    end

    it "marks the summary tile holding a record" do
      running = catalog_sport("running")
      workout = create(:workout, user:, sport: running, distance: 5_000.0)
      sign_in_user

      get workout_path(workout)

      expect(response.body).to include(I18n.t("medals.record", record: I18n.t("records.types.fd")))
    end

    it "carries the record as a card stamp on its primary tile, never as a badge" do
      running = catalog_sport("running")
      record_workout = create(:workout, user:, sport: running, distance: 10_000.0,
                                       duration: 3_700, moving_time: 3_600, pause_time: 100,
                                       average_pace: 240, ascent: 200.0)
      plain_workout = create(:workout, user:, sport: running, distance: 5_000.0,
                                      duration: 1_900, moving_time: 1_800, pause_time: 100,
                                      average_pace: 300, ascent: 50.0)
      sign_in_user

      get workout_path(record_workout)

      page = Nokogiri::HTML(response.body)
      trophy_label = I18n.t("medals.record", record: I18n.t("records.types.fd"))
      tiles = page.css(".allure-metric-tile")
      distance_tile = tiles.find { |tile| tile.at_css("dt").text.include?(I18n.t("workouts.show.metrics.distance")) }

      expect(tiles).not_to be_empty
      expect(tiles.all? { |tile| tile.at_css(".card-stamp .card-stamp-icon.allure-stamp--gold .ti-trophy") }).to be(true)
      expect(distance_tile.at_css(".visually-hidden").text).to eq(trophy_label)
      expect(distance_tile["data-bs-title"]).to eq(trophy_label)
      expect(distance_tile["data-controller"]).to eq("tooltip")
      expect(tiles.flat_map { |tile| tile.css(".badge") }).to be_empty

      get workout_path(plain_workout)

      plain_tiles = Nokogiri::HTML(response.body).css(".allure-metric-tile")
      expect(plain_tiles.flat_map { |tile| tile.css(".card-stamp") }).to be_empty
      expect(plain_tiles.flat_map { |tile| tile.css(".badge") }).to be_empty
    end

    it "marks the biggest climb when the workout holds MC" do
      running = catalog_sport("running")
      workout = create(:workout, user:, sport: running)
      create(:detected_lap, :climb, workout:, number: 1, ascent: 40.0, name: "Petite côte")
      create(:detected_lap, :climb, workout:, number: 2, ascent: 180.0, name: "Grande côte")
      Records::RecomputeService.new(user:, sport: running).call
      sign_in_user

      get workout_path(workout)

      expect(response.body).to match(/#{Regexp.escape("Grande côte")}\s*<span class="ms-1"[^>]*data-controller="tooltip"[^>]*>\s*<i class="ti ti-trophy allure-medal allure-medal--gold"/)
      expect(response.body).not_to match(/#{Regexp.escape("Petite côte")}\s*<span class="ms-1"[^>]*data-controller="tooltip"/)
    end

    it "shows the published badge and tile trophy to a permitted viewer" do
      owner = create(:user)
      running = catalog_sport("running")
      workout = create(:workout, user: owner, sport: running, distance: 5_000.0)
      create(:track_segment, workout:)
      create(:effort_record, user: owner, sport: running, workout:,
                             distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_500)
      profile = create(:publishing_profile, user: owner,
                        settings: PublishingProfile::DEFAULT_SETTINGS.merge(
                          "records" => true, "metrics" => %w[distance],
                          "mask_start" => false, "mask_finish" => false
                        ))
      publish_workout!(user: owner, workout:, profile:)
      sign_in_user

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("workouts.show.records.badge_short"))
      expect(response.body).to include(I18n.t("records.types.fd"), I18n.t("records.distances.km5"))
      expect(response.body).to include(I18n.t("medals.record", record: I18n.t("records.types.fd")))
      expect(response.body).not_to include(I18n.t("medals.record", record: I18n.t("records.types.ha")))
    end

    it "never shows records to a non-owner" do
      owner = create(:user)
      running = catalog_sport("running")
      public_workout = create(:workout, user: owner, sport: running, title: "Public of owner")
      create(:track_segment, workout: public_workout)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout: public_workout, profile:)
      sign_in_user

      get workout_path(public_workout)

      expect(response).to have_http_status(:ok)
      # Scoped to the record markers: the footer's release notes may name
      # records in prose.
      expect(response.parsed_body.at_css(".allure-record-badge, .ti-trophy")).to be_nil
      expect(response.body).not_to include(I18n.t("medals.record", record: I18n.t("records.types.fd")))
    end
  end
end
