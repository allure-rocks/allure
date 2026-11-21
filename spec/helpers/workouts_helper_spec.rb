# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutsHelper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#format_decimal and the unit formatters" do
    it "print numbers in the page locale" do
      expect(helper.format_decimal(4381)).to eq("4\u202F381")
      expect(helper.format_decimal(12.345, precision: 1)).to eq("12,3")
      expect(helper.format_distance(345_300, unit_system: "metric", precision: 1)).to eq("345,3 km")
      expect(helper.format_elevation(4381, unit_system: "metric")).to eq("4\u202F381 m")
      expect(helper.format_speed(5, unit_system: "metric")).to eq("18,0 km/h")
      expect(helper.format_decimal(nil)).to eq("—")

      I18n.with_locale(:en) do
        expect(helper.format_decimal(4381)).to eq("4,381")
        expect(helper.format_distance(345_300, unit_system: "metric", precision: 1)).to eq("345.3 km")
        expect(helper.format_speed(5, unit_system: "metric")).to eq("18.0 km/h")
      end
    end
  end

  describe "#workout_missing_metric_labels" do
    it "names each unrecorded channel once, in display order" do
      items = [
        { key: :average_heart_rate, label: "Fréquence cardiaque moyenne", value: "—" },
        { key: :max_heart_rate, label: "Fréquence cardiaque maximale", value: "—" },
        { key: :calories, label: "Calories", value: "—" },
        { key: :grade_adjusted_pace, label: "Allure ajustée (GAP)", value: "—" },
        { key: :max_speed, label: "Vitesse maximale", value: "40.1 km/h" }
      ]

      expect(helper.workout_missing_metric_labels(items)).to eq(
        [ I18n.t("workouts.show.metrics.families.heart_rate"), "calories", "allure ajustée (GAP)" ]
      )
    end
  end

  describe "#publication_withheld_fields" do
    it "lists the optional fields the profile leaves out, metrics only when none are shared" do
      profile = build(:publishing_profile, settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "device" => false, "commute" => false, "records" => false, "metrics" => []
      ))

      withheld = helper.publication_withheld_fields(profile)

      expect(withheld).to include(
        I18n.t("publishing_profiles.settings.metrics_title"),
        I18n.t("publishing_profiles.settings.device"),
        I18n.t("publishing_profiles.settings.commute")
      )
      expect(withheld).not_to include(I18n.t("publishing_profiles.settings.title"))
      expect(withheld & helper.publication_preview_fields(profile)).to be_empty
    end
  end

  describe "#format_started_at" do
    it "uses the application time zone for anonymous viewers" do
      helper.define_singleton_method(:current_user) { nil }
      time = Time.utc(2026, 8, 23, 23, 30)

      Time.use_zone("UTC") do
        expect(helper.format_started_at(time)).to eq(I18n.l(time.in_time_zone, format: :long))
      end
    end
  end

  describe "#smart_started_at" do
    let(:viewer) { build(:user, time_zone: "Europe/Paris") }
    let(:paris) { Time.find_zone("Europe/Paris") }

    before do
      v = viewer
      helper.define_singleton_method(:current_user) { v }
    end

    it "labels today, yesterday and the day before with the clock time" do
      travel_to(paris.local(2026, 9, 16, 12, 0, 0)) do
        expect(helper.smart_started_at(paris.local(2026, 9, 16, 14, 30))).to eq("Aujourd'hui 14:30")
        expect(helper.smart_started_at(paris.local(2026, 9, 15, 7, 30))).to eq("Hier 07:30")
        expect(helper.smart_started_at(paris.local(2026, 9, 14, 8, 2))).to eq("Avant-hier 08:02")
      end
    end

    it "falls back to the short date beyond two days" do
      travel_to(paris.local(2026, 9, 16, 12, 0, 0)) do
        expect(helper.smart_started_at(paris.local(2026, 9, 12, 8, 2))).to eq("12 sept. 08:02")
      end
    end

    it "anchors the day on the viewer's time zone" do
      viewer.time_zone = "Pacific/Auckland"
      # 15 Sept 23:00 UTC is already the 16th at 11:00 in Auckland, while the
      # frozen UTC "now" is still the 16th: the label must read "today".
      travel_to(Time.utc(2026, 9, 16, 1, 0)) do
        expect(helper.smart_started_at(Time.utc(2026, 9, 15, 23, 0))).to start_with("Aujourd'hui")
      end
    end

    it "renders an em dash without a time" do
      expect(helper.smart_started_at(nil)).to eq("—")
    end
  end

  describe "#format_duration_human" do
    it "scales from seconds to hours and minutes" do
      expect(helper.format_duration_human(45)).to eq("45 s")
      expect(helper.format_duration_human(48 * 60)).to eq("48 min")
      expect(helper.format_duration_human(2 * 3600)).to eq("2 h")
      expect(helper.format_duration_human(3600 + 25 * 60)).to eq("1 h 25 min")
    end

    it "renders an em dash without a duration" do
      expect(helper.format_duration_human(nil)).to eq("—")
    end
  end

  describe "#format_duration_delta" do
    it "signs seconds under a minute and clock time beyond" do
      expect(helper.format_duration_delta(8)).to eq("+8 s")
      expect(helper.format_duration_delta(-8)).to eq("−8 s")
      expect(helper.format_duration_delta(72)).to eq("+1:12")
      expect(helper.format_duration_delta(-3725)).to eq("−1:02:05")
      expect(helper.format_duration_delta(0)).to eq("0 s")
      expect(helper.format_duration_delta(nil)).to eq("—")
    end
  end

  describe "#format_pace" do
    before { helper.define_singleton_method(:current_user) { nil } }

    it "renders the viewer's kilometre by default" do
      expect(helper.format_pace(300)).to eq("5:00 #{I18n.t('units.pace.per_km')}")
    end

    it "renders a sport's fixed basis over its own distance in either unit system" do
      rowing = build(:sport, pace_speed_display: "pace", pace_basis_metres: 500)

      expect(helper.format_pace(300, sport: rowing)).to eq("2:30 #{I18n.t('units.pace.per_500m')}")
      expect(helper.format_pace(300, unit_system: "imperial", sport: rowing))
        .to eq("2:30 #{I18n.t('units.pace.per_500m')}")
    end

    it "falls back to the metre symbol for a non-curated basis" do
      sport = build(:sport, pace_speed_display: "pace", pace_basis_metres: 250)

      expect(helper.format_pace(300, sport:)).to eq("1:15 /250 #{I18n.t('units.symbols.metre')}")
    end
  end

  describe "#workout_lap_tabs" do
    it "passes the personal places to the best-efforts pane" do
      workout = build(:workout)
      effort = build(:best_effort, workout:, distance_key: "km5")

      tabs = helper.workout_lap_tabs(
        workout:, efforts: [], recorded: [], laps: [], climbs: [], descents: [], stops: [],
        intervals: [], splits: [], best_efforts: [ effort ], best_effort_places: { 7 => 2 }
      )

      pane = tabs.find { |tab| tab[:key] == "best_efforts" }
      expect(pane[:count]).to eq(1)
      expect(pane[:icon]).to eq("stopwatch")
      expect(pane[:locals][:places]).to eq({ 7 => 2 })
    end
  end

  describe "#held_record_labels" do
    it "lists classic records then best-effort distances, hiding types the sport cannot express" do
      sport = build(:sport, pace_speed_display: "pace", records_elevation: false)
      records = %w[AS HA FD].map { |type| Record.new(record_type: type) }
      efforts = [ BestEffort.new(distance_key: "km5") ]

      labels = helper.held_record_labels(records, efforts, sport:)

      expect(labels).to eq([ I18n.t("records.types.fd"), I18n.t("records.distances.km5") ])
    end
  end

  describe "#record_labels_by_metric_key" do
    it "maps visible record types to their summary tile keys" do
      sport = build(:sport, pace_speed_display: "speed", records_elevation: false)
      records = %w[FD AS AP HA MC].map { |type| Record.new(record_type: type) }

      labels = helper.record_labels_by_metric_key(records, sport:)

      expect(labels).to eq(
        distance: I18n.t("records.types.fd"),
        average_speed: I18n.t("records.types.as")
      )
    end
  end

  describe "#pace_speed_cell" do
    before { helper.define_singleton_method(:current_user) { nil } }

    it "renders the grade-adjusted pace as a quiet secondary line" do
      sport = build(:sport, pace_speed_display: "pace")
      cell = helper.pace_speed_cell(average_pace: 300, average_speed: 3.33, sport:, grade_adjusted_pace: 280)

      expect(cell).to include("GAP")
      expect(cell).to include(helper.format_pace(280))
    end

    it "carries the grade-adjusted pace explanation as a Bootstrap tooltip, not a native title" do
      sport = build(:sport, pace_speed_display: "pace")
      cell = helper.pace_speed_cell(average_pace: 300, average_speed: 3.33, sport:, grade_adjusted_pace: 280)

      gap = Nokogiri::HTML.fragment(cell).at_css("small.d-block")

      expect(gap["data-controller"]).to eq("tooltip")
      expect(gap["data-bs-title"]).to eq(I18n.t("workouts.show.metrics.grade_adjusted_pace"))
      expect(gap["title"]).to be_nil
    end

    it "omits the grade-adjusted pace when nil" do
      sport = build(:sport, pace_speed_display: "pace")
      cell = helper.pace_speed_cell(average_pace: 300, average_speed: 3.33, sport:, grade_adjusted_pace: nil)

      expect(cell).not_to include("GAP")
    end
  end

  describe "#workout_metric_items" do
    before { helper.define_singleton_method(:current_user) { nil } }

    def primary_keys(items)
      items.select { |item| item[:primary] }.sort_by { |item| item[:priority] }.map { |item| item[:key] }
    end

    it "hides the grade-adjusted pace when not recorded" do
      workout = build(:workout, grade_adjusted_pace: nil)
      keys = helper.workout_metric_items(workout).map { |item| item[:key] }

      expect(keys).not_to include(:grade_adjusted_pace)
    end

    it "includes the recorded grade-adjusted pace on a pace sport" do
      workout = build(:workout, sport: build(:sport, pace_speed_display: "pace"), grade_adjusted_pace: 250)
      item = helper.workout_metric_items(workout).find { |entry| entry[:key] == :grade_adjusted_pace }

      expect(item[:value]).to eq(helper.format_pace(250))
    end

    it "lists no pace on a sport that reads its speed" do
      workout = build(:workout, sport: build(:sport, pace_speed_display: "speed"),
                                average_pace: 200, best_pace: 180, grade_adjusted_pace: 190,
                                average_speed: 5.0, max_speed: 6.0)
      keys = helper.workout_metric_items(workout).map { |item| item[:key] }

      expect(keys).to include(:average_speed, :max_speed)
      expect(keys).not_to include(:average_pace, :best_pace, :grade_adjusted_pace)
    end

    it "lists no speed on a sport that reads its pace" do
      workout = build(:workout, sport: build(:sport, pace_speed_display: "pace"),
                                average_pace: 200, best_pace: 180,
                                average_speed: 5.0, max_speed: 6.0)
      keys = helper.workout_metric_items(workout).map { |item| item[:key] }

      expect(keys).to include(:average_pace, :best_pace)
      expect(keys).not_to include(:average_speed, :max_speed)
    end

    it "keeps both channels on a sport that declares both" do
      workout = build(:workout, sport: build(:sport, pace_speed_display: "pace_and_speed"),
                                average_pace: 200, average_speed: 5.0, max_speed: 6.0)
      keys = helper.workout_metric_items(workout).map { |item| item[:key] }

      expect(keys).to include(:average_pace, :average_speed, :max_speed)
    end

    it "never lists the raw point count as a metric" do
      workout = build(:workout, points_count: 13_128)

      expect(helper.workout_metric_items(workout).map { |item| item[:key] }).not_to include(:points_count)
    end

    it "drops speed and prefers power for a fixed-basis sport" do
      rowing = build(:sport, pace_speed_display: "pace", pace_basis_metres: 500)
      workout = build(:workout, sport: rowing, average_pace: 240, average_speed: 4.16, max_speed: 4.5,
                                average_power: 210, ascent: 120)
      items = helper.workout_metric_items(workout)

      expect(items.map { |item| item[:key] }).not_to include(:average_speed, :max_speed)
      expect(items.select { |item| item[:primary] }.sort_by { |item| item[:priority] }.map { |item| item[:key] })
        .to eq(%i[distance moving_time average_pace average_power])
      expect(items.find { |item| item[:key] == :average_pace }[:value]).to eq("2:00 /500m")
      expect(items.find { |item| item[:key] == :average_power }[:value]).to eq("210 W")
    end

    it "keeps ascent as the fourth tile when a fixed-basis sport recorded no power" do
      rowing = build(:sport, pace_speed_display: "pace", pace_basis_metres: 500)
      workout = build(:workout, sport: rowing, average_pace: 240, average_speed: 4.16,
                                average_power: nil, ascent: 120)

      expect(helper.workout_metric_items(workout).select { |item| item[:primary] }
        .sort_by { |item| item[:priority] }.map { |item| item[:key] })
        .to eq(%i[distance moving_time average_pace ascent])
    end

    it "leads a power-led virtual ride with its power and keeps the ascent" do
      virtual = build(:sport, virtual: true, pace_speed_display: "speed")
      workout = build(:workout, sport: virtual, average_speed: 8.0, average_power: 210, ascent: 120)

      items = helper.workout_metric_items(workout)

      expect(primary_keys(items)).to eq(%i[distance moving_time average_power ascent])
      expect(items.find { |item| item[:key] == :average_power }[:value]).to eq("210 W")
    end

    it "keeps the speed when a power-led virtual ride recorded no power" do
      virtual = build(:sport, virtual: true, pace_speed_display: "speed")
      workout = build(:workout, sport: virtual, average_speed: 8.0, average_power: nil, ascent: 120)

      expect(primary_keys(helper.workout_metric_items(workout)))
        .to eq(%i[distance moving_time average_speed ascent])
    end

    it "promotes the power of a positionless virtual ride and keeps a fourth channel" do
      virtual = build(:sport, virtual: true, pace_speed_display: "speed")
      workout = build(:workout, :unpositioned, sport: virtual, average_speed: 8.0,
                                               average_power: 210, average_heart_rate: 140)

      expect(primary_keys(helper.workout_metric_items(workout)))
        .to eq(%i[distance moving_time average_power average_heart_rate])
    end

    it "keeps the speed tile for a participant, whose credited set has no power" do
      virtual = build(:sport, virtual: true, pace_speed_display: "speed")
      workout = build(:workout, sport: virtual, average_speed: 8.0, average_power: 210, ascent: 120)

      items = helper.participant_metric_items(workout)

      expect(items.map { |item| item[:key] }).not_to include(:average_power)
      expect(primary_keys(items)).to eq(%i[distance moving_time average_speed ascent])
    end
  end

  describe "#workout_chart_display_series" do
    before { helper.define_singleton_method(:current_user) { nil } }

    it "opens a power-led virtual ride on its power and keeps the speed" do
      workout = build(:workout, sport: build(:sport, virtual: true, pace_speed_display: "speed"))

      expect(helper.workout_chart_display_series(workout, %i[elevation speed heart_rate power]))
        .to eq(%i[elevation power speed heart_rate])
    end

    it "keeps the sport order for an ordinary ride" do
      workout = build(:workout, sport: build(:sport, pace_speed_display: "speed"))

      expect(helper.workout_chart_display_series(workout, %i[elevation speed power]))
        .to eq(%i[elevation speed power])
    end
  end

  describe "#elevation_change" do
    before { helper.define_singleton_method(:current_user) { nil } }

    it "keeps each figure whole and names its channel for screen readers" do
      I18n.with_locale(:fr) do
        html = Nokogiri::HTML5.fragment(helper.elevation_change(ascent: 554.0, descent: 8.0))

        expect(html.css("span.text-nowrap").map { |span| span.text.squish })
          .to eq([ "↑ Dénivelé positif 554 m", "↓ Dénivelé négatif 8 m" ])
        expect(html.css("span.text-nowrap > span[aria-hidden=true]").map(&:text)).to eq([ "↑", "↓" ])
        expect(html.css("span.visually-hidden").map(&:text)).to eq([ "Dénivelé positif", "Dénivelé négatif" ])
      end
    end

    it "leads with the descent on a descent list" do
      I18n.with_locale(:fr) do
        html = Nokogiri::HTML5.fragment(helper.elevation_change(ascent: 10.0, descent: 200.0, lead: :descent))

        expect(html.css("span.text-nowrap").map { |span| span.text.squish })
          .to eq([ "↓ Dénivelé négatif 200 m", "↑ Dénivelé positif 10 m" ])
      end
    end
  end

  describe "#analysis_row_attributes" do
    it "marks the row as a focusable analysis range" do
      attributes = helper.analysis_row_attributes(100.0, 500.0)

      expect(attributes[:tabindex]).to eq(0)
      expect(attributes[:data]).to include(analysis_range: "", start_distance: 100.0, end_distance: 500.0)
    end
  end

  describe "#recorded_lap_ranges" do
    it "maps cumulative lap distances onto the workout total" do
      laps = [ build(:lap, distance: 1_000.0), build(:lap, distance: 1_000.0), build(:lap, distance: 500.0) ]

      expect(helper.recorded_lap_ranges(laps, 2_500.0)).to eq([
        { start: 0.0, end: 1_000.0 },
        { start: 1_000.0, end: 2_000.0 },
        { start: 2_000.0, end: 2_500.0 }
      ])
    end

    it "scales when the lap total drifts from the workout distance" do
      laps = [ build(:lap, distance: 400.0), build(:lap, distance: 400.0) ]

      expect(helper.recorded_lap_ranges(laps, 1_000.0)).to eq([
        { start: 0.0, end: 500.0 },
        { start: 500.0, end: 1_000.0 }
      ])
    end
  end

  describe "#split_ranges" do
    it "returns cumulative ranges aligned with the splits" do
      splits = [
        instance_double(Allure::Gpx::Splits::Split, distance: 1_000.0),
        instance_double(Allure::Gpx::Splits::Split, distance: 609.344)
      ]

      expect(helper.split_ranges(splits)).to eq([
        { start: 0.0, end: 1_000.0 },
        { start: 1_000.0, end: 1_609.3 }
      ])
    end
  end

  describe "#pace_speed_values" do
    before { helper.define_singleton_method(:current_user) { nil } }

    it "follows the sport display preference" do
      pace_sport = build(:sport, pace_speed_display: "pace")
      speed_sport = build(:sport, pace_speed_display: "speed")
      both_sport = build(:sport, pace_speed_display: "pace_and_speed")

      expect(helper.pace_speed_values(average_pace: 300, average_speed: 3.33, sport: pace_sport))
        .to eq([ helper.format_pace(300), nil ])
      expect(helper.pace_speed_values(average_pace: 300, average_speed: 3.33, sport: speed_sport))
        .to eq([ helper.format_speed(3.33), nil ])

      primary, secondary = helper.pace_speed_values(average_pace: 300, average_speed: 3.33, sport: both_sport)
      expect(primary).to eq(helper.format_pace(300))
      expect(secondary).to eq(helper.format_speed(3.33))
    end

    it "falls back to the other value when the preferred one is missing" do
      sport = build(:sport, pace_speed_display: "pace")

      expect(helper.pace_speed_values(average_pace: nil, average_speed: 3.33, sport:))
        .to eq([ helper.format_speed(3.33), nil ])
    end

    it "renders the fixed basis and never speed for a rowing sport" do
      rowing = build(:sport, pace_speed_display: "pace", pace_basis_metres: 500)

      expect(helper.pace_speed_values(average_pace: 240, average_speed: 4.16, sport: rowing))
        .to eq([ "2:00 /500m", nil ])
    end

    it "derives the fixed-basis pace from speed when the pace is missing" do
      rowing = build(:sport, pace_speed_display: "pace", pace_basis_metres: 500)

      expect(helper.pace_speed_values(average_pace: nil, average_speed: 4.0, sport: rowing))
        .to eq([ "2:05 /500m", nil ])
    end
  end

  describe "#effort_cell" do
    before { helper.define_singleton_method(:current_user) { nil } }

    it "leads a power-led virtual ride with its watts and keeps the speed quiet" do
      virtual = build(:sport, virtual: true, pace_speed_display: "speed")
      cell = helper.effort_cell(average_pace: 200, average_speed: 8.0, average_power: 210, sport: virtual)

      expect(cell).to include(helper.format_power(210))
      expect(cell).to include(helper.format_speed(8.0))
      expect(cell).to include("text-secondary")
    end

    it "keeps the pace/speed cell for every other sport" do
      road = build(:sport, pace_speed_display: "speed")
      cell = helper.effort_cell(average_pace: 200, average_speed: 8.0, average_power: 210, sport: road)

      expect(cell).to eq(helper.pace_speed_cell(average_pace: 200, average_speed: 8.0, sport: road))
    end

    it "falls back to the speed when a power-led row recorded no power" do
      virtual = build(:sport, virtual: true, pace_speed_display: "speed")
      cell = helper.effort_cell(average_pace: 200, average_speed: 8.0, average_power: nil, sport: virtual)

      expect(cell).to eq(helper.pace_speed_cell(average_pace: 200, average_speed: 8.0, sport: virtual))
    end
  end

  describe "#effort_column_label" do
    it "names the column after what its cells print" do
      expect(helper.effort_column_label(build(:sport, pace_speed_display: "pace"), scope: "workouts.show.laps"))
        .to eq(I18n.t("workouts.show.laps.pace"))
      expect(helper.effort_column_label(build(:sport, pace_speed_display: "speed"), scope: "workouts.show.laps"))
        .to eq(I18n.t("workouts.show.laps.speed"))
      expect(helper.effort_column_label(build(:sport, virtual: true, pace_speed_display: "speed"), scope: "workouts.show.laps"))
        .to eq(I18n.t("workouts.show.laps.power"))
    end
  end

  describe "#effort_analysis_range" do
    it "maps the effort point indexes to cumulative distances" do
      workout = create(:workout)
      create(:track_segment, workout:)
      segment = create(:segment, user: workout.user, sport: workout.sport)
      effort = create(:segment_effort, segment:, workout:, user: workout.user, sport: workout.sport)

      expect(helper.effort_analysis_range(workout, effort)).to eq([ 0.0, 250.0 ])
    end
  end

  describe "#pagy_url_for" do
    let(:pagy) { double("pagy", page: 2, last: 3, options: { page_key: "page" }) }

    it "round-trips ordinary filter params on the current path" do
      allow(helper.request).to receive(:query_parameters).and_return(
        { "public" => "1", "sports" => [ "3" ], "page" => "3" }
      )
      allow(helper.request).to receive(:path).and_return("/feed")

      expect(helper.send(:pagy_url_for, pagy, 2)).to eq("/feed?page=2&amp;public=1&amp;sports%5B%5D=3")
    end

    it "never interprets reserved URL options from the query string" do
      allow(helper.request).to receive(:query_parameters).and_return(
        { "host" => %(evil.example"><script>alert(1)</script>), "protocol" => "javascript" }
      )
      allow(helper.request).to receive(:path).and_return("/@marie")

      url = helper.send(:pagy_url_for, pagy, 2)

      expect(url).to start_with("/@marie?")
      expect(url).to include("host=evil.example%22%3E%3Cscript%3E")
      expect(url).not_to match(/["<>]/)
    end

    it "keeps independent profile pagers and journal filters separate" do
      allow(pagy).to receive(:options).and_return(page_key: "segments_page")
      allow(helper.request).to receive(:query_parameters).and_return(
        { "page" => "2", "segments_page" => "1", "sport" => "label:Hiking", "period" => "year" }
      )
      allow(helper.request).to receive(:path).and_return("/people/remote/demo@remote.example")

      query = helper.send(:pagy_url_for, pagy, 3).split("?", 2).last

      expect(Rack::Utils.parse_nested_query(CGI.unescapeHTML(query))).to include(
        "page" => "2", "segments_page" => "3", "sport" => "label:Hiking", "period" => "year"
      )
    end
  end

  describe "#workout_panel_filter_count" do
    it "keeps a preset period out of the drawer count but in the active filters" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(period: "year"))

      expect(helper.workout_panel_filter_count).to eq(0)
      expect(helper.workout_filters_active?).to be(true)
      expect(helper.workout_filter_chips).to be_empty
    end

    it "counts the custom range, publication, commute and search filters, never the sports" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(
          sports: [ "3", "7" ], period: "custom", publication: "published",
          commute: "commute", q: "ride", sort: "distance", direction: "asc", page: "2"
        )
      )

      expect(helper.workout_panel_filter_count).to eq(4)
      expect(helper.workout_panel_filters_active?).to be(true)
    end

    it "ignores the defaults and the non-filter params" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(
          period: "all", publication: "all", commute: "all", q: "", sort: "distance", direction: "desc"
        )
      )

      expect(helper.workout_panel_filter_count).to eq(0)
      expect(helper.workout_panel_filters_active?).to be(false)
      expect(helper.workout_filters_active?).to be(false)
    end

    it "counts the place filter" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(place: "Rochelune"))

      expect(helper.workout_panel_filter_count).to eq(1)
      expect(helper.workout_panel_filters_active?).to be(true)
    end

    it "keeps the sport selection out of the panel but in the active filters" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(sports: [ "3" ]))

      expect(helper.workout_panel_filter_count).to eq(0)
      expect(helper.workout_panel_filters_active?).to be(false)
      expect(helper.workout_filters_active?).to be(true)
    end
  end

  describe "#workout_filter_chips" do
    it "adds a removable chip for the place filter" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(place: "Rochelune"))

      chips = helper.workout_filter_chips

      expect(chips.map { |chip| chip[:label] }).to eq([ "Rochelune" ])
      expect(chips.first[:url]).to eq("/workouts")
    end

    it "removes only the place from the query string" do
      allow(helper).to receive(:params).and_return(
        ActionController::Parameters.new(place: "Rochelune", period: "year")
      )

      chips = helper.workout_filter_chips
      place_chip = chips.find { |chip| chip[:label] == "Rochelune" }

      expect(place_chip[:url]).to eq("/workouts?period=year")
    end
  end

  describe "#workout_elevation_notice" do
    let(:user) { create(:user, elevation_enrichment_enabled: true) }
    let(:sport) { catalog_sport("running") }
    let(:workout) { create(:workout, user:, sport:, min_elevation: nil, max_elevation: nil) }

    before do
      viewer = user
      helper.define_singleton_method(:current_user) { viewer }
      allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
    end

    it "returns nil for a workout that has elevation" do
      expect(helper.workout_elevation_notice(create(:workout, user:, sport:))).to be_nil
    end

    it "returns nil for a viewer who is not the owner" do
      viewer = create(:user)
      helper.define_singleton_method(:current_user) { viewer }

      expect(helper.workout_elevation_notice(workout)).to be_nil
    end

    it "names a sport that does not record elevation" do
      bare = create(:workout, user:, sport: catalog_sport("rowing"), min_elevation: nil, max_elevation: nil)

      expect(helper.workout_elevation_notice(bare)).to eq(:sport_without_elevation)
    end

    it "reports a missing provider" do
      allow(Allure::Elevation::Config).to receive(:configured?).and_return(false)

      expect(helper.workout_elevation_notice(workout)).to eq(:provider_missing)
    end

    it "reports an account that did not opt in" do
      user.update!(elevation_enrichment_enabled: false)

      expect(helper.workout_elevation_notice(workout)).to eq(:opt_out)
    end

    it "reports a pending request" do
      workout.update!(elevation_source_requested: "dem")

      expect(helper.workout_elevation_notice(workout)).to eq(:pending)
    end

    it "reports a failed enrichment" do
      create(:workout_elevation, workout:, status: "failed")

      expect(helper.workout_elevation_notice(workout)).to eq(:failed)
    end

    it "reports an unavailable enrichment" do
      create(:workout_elevation, workout:, status: "unavailable")

      expect(helper.workout_elevation_notice(workout)).to eq(:unavailable)
    end

    it "reports an idle enrichment when no terrain profile exists" do
      expect(helper.workout_elevation_notice(workout)).to eq(:idle)
    end

    it "reports a cached terrain profile that was never applied" do
      create(:workout_elevation, workout:, status: "ready")

      expect(helper.workout_elevation_notice(workout)).to eq(:idle)
    end

    it "stays silent when the terrain profile is already effective" do
      workout.update!(elevation_source: "dem")
      create(:workout_elevation, workout:, status: "ready")

      expect(helper.workout_elevation_notice(workout)).to be_nil
    end
  end

  describe "#analysis_step" do
    it "builds a route step with a plain-text detail, the localized source, and its icon" do
      step = helper.analysis_step(100.0, 500.0, name: "Montée 1", detail: "4:00 · 1,2 km", source: "climb", icon: "mountain")

      expect(step).to eq(
        "distance" => 100.0,
        "endDistance" => 500.0,
        "name" => "Montée 1",
        "detail" => "4:00 · 1,2 km",
        "source" => "climb",
        "sourceLabel" => I18n.t("workouts.show.laps.sources.climb"),
        "icon" => "mountain"
      )
    end
  end

  describe "#analysis_markers" do
    it "anchors climbs on their summit and descents on their own summit" do
      climb = build(:detected_lap, :climb, start_distance: 400.0, end_distance: 800.0)
      descent = build(:detected_lap, :descent, start_distance: 900.0, end_distance: 1_400.0)

      expect(helper.analysis_markers([ climb ], "mountain")).to eq(
        [ { "distance" => 800.0, "glyph" => "mountain", "label" => nil } ]
      )
      expect(helper.analysis_markers([ descent ], "mountain", distance: :start_distance)).to eq(
        [ { "distance" => 900.0, "glyph" => "mountain", "label" => nil } ]
      )
    end
  end

  describe "#workout_place_label" do
    def workout_with_places(places)
      build(:workout, places:)
    end

    it "joins the route places in order" do
      workout = workout_with_places([
        { "name" => "Valmorin", "kind" => "village" },
        { "name" => "Cimefroide", "kind" => "town" },
        { "name" => "Rochelune", "kind" => "city" }
      ])

      expect(helper.workout_place_label(workout)).to eq("Valmorin · Cimefroide · Rochelune")
    end

    it "returns a lone place as its name" do
      workout = workout_with_places([ { "name" => "Rochelune", "kind" => "city" } ])

      expect(helper.workout_place_label(workout)).to eq("Rochelune")
    end

    it "accepts symbol keys and ignores nameless entries" do
      workout = workout_with_places([ { name: "", kind: "town" }, { name: "Cimefroide", kind: "town" } ])

      expect(helper.workout_place_label(workout)).to eq("Cimefroide")
    end

    it "returns nil without places" do
      expect(helper.workout_place_label(workout_with_places([]))).to be_nil
    end
  end
end
