# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeHelper do
  let(:user) { build(:user, unit_system: "metric") }

  before do
    viewer = user
    helper.define_singleton_method(:current_user) { viewer }
  end

  describe "#comparison_badge" do
    it "renders nothing when there is no previous window" do
      comparison = Allure::Stats::Trends.compare(current: 10, previous: 0)

      expect(helper.comparison_badge(comparison)).to be_nil
    end

    it "renders an accessible upward move" do
      comparison = Allure::Stats::Trends.compare(current: 120, previous: 100)
      percent = helper.number_to_percentage(20.0, precision: 0)

      html = helper.comparison_badge(comparison)

      expect(html).to include("hub-delta--up", "+20")
      expect(html).to include(I18n.t("me.summary.comparison.up", percent:))
    end

    it "renders a flat move without a signed percentage" do
      comparison = Allure::Stats::Trends.compare(current: 100, previous: 100)

      html = helper.comparison_badge(comparison)

      expect(html).to include("hub-delta--flat", "0 %")
      expect(html).to include("Stable par rapport à la période précédente")
    end
  end

  describe "#mix_value" do
    it "formats each mix metric in the viewer's units" do
      expect(helper.mix_value("distance", 10_000)).to eq("10,0 km")
      expect(helper.mix_value("duration", 3600)).to eq("1:00:00")
      expect(helper.mix_value("workouts", 3)).to eq("3")
    end
  end

  describe "#pulse_chart_payload" do
    let(:today) { Date.new(2026, 9, 16) }
    let(:rows) do
      [
        { period: Date.new(2026, 9, 7), workouts: 0, distance: 0.0, duration: 0, ascent: 0.0, sports: {} },
        { period: Date.new(2026, 9, 14), workouts: 2, distance: 10_000.0, duration: 3600, ascent: 120.0,
          sports: { 1 => {}, 2 => {} } }
      ]
    end

    before { helper.instance_variable_set(:@today, today) }

    def intensity_for(rows)
      Allure::Stats::Intensity.new(rows)
    end

    it "carries one labelled, scored and formatted point per week plus the highlight and peak flags" do
      intensity = intensity_for(rows)
      payload = helper.pulse_chart_payload(
        intensity,
        period_range: Date.new(2026, 9, 14)..Date.new(2026, 9, 16),
        points: intensity.rows
      )

      expect(payload[:granularity]).to eq("week")
      expect(payload[:points].first).to eq(
        label: I18n.l(Date.new(2026, 9, 7), format: :short_year),
        tooltip_label: "Semaine du 7 septembre",
        score: 0,
        score_label: "Repos",
        rest: true,
        in_period: false,
        detail: "Repos",
        url: nil,
        open_label: nil,
        peak: false
      )
      expect(payload[:points].last).to include(
        label: I18n.l(Date.new(2026, 9, 14), format: :short),
        tooltip_label: "Semaine du 14 septembre",
        score: 100,
        rest: false,
        in_period: true,
        peak: true
      )
      expect(payload[:points].last[:detail]).to eq("2 activités · 10,0 km · 120 m · 1 h · 2 sports")
      expect(payload[:points].last[:open_label]).to eq("Voir les 2 activités")
      expect(payload[:points].last[:url]).to include("period=custom", "from=2026-09-14", "to=2026-09-16")
      expect(payload[:older_url]).to be_nil
    end

    it "carries the workouts URL of each active week, with the sport filter" do
      helper.instance_variable_set(:@filter_sport, build(:sport, id: 7))
      intensity = intensity_for(rows)
      payload = helper.pulse_chart_payload(intensity, period_range: nil, points: intensity.rows)

      expect(payload[:points].first[:url]).to be_nil
      expect(payload[:points].last[:url]).to include(
        "period=custom", "from=2026-09-14", "to=2026-09-16", "sports%5B%5D=7"
      )
    end

    it "opens the activity itself for a week holding a single one" do
      helper.instance_variable_set(:@pulse_single_workouts, { Date.new(2026, 9, 14) => "abc123" })
      intensity = intensity_for(rows)
      payload = helper.pulse_chart_payload(intensity, period_range: nil, points: intensity.rows)

      expect(payload[:points].last[:url]).to eq(helper.workout_path("abc123"))
    end

    it "names a week with the year when it is not the current one" do
      intensity = intensity_for([ rows.first.merge(period: Date.new(2025, 9, 8)) ])

      payload = helper.pulse_chart_payload(intensity, period_range: nil, points: intensity.rows)

      expect(payload[:points].first[:label]).to eq(I18n.l(Date.new(2025, 9, 8), format: :short_year))
      expect(payload[:points].first[:tooltip_label]).to eq("Semaine du 8 septembre 2025")
      expect(payload[:points].first[:in_period]).to be(true)
    end

    it "carries the older window URL and the chart labels" do
      intensity = intensity_for(rows)
      payload = helper.pulse_chart_payload(
        intensity,
        period_range: nil,
        points: intensity.rows,
        older_url: "/me/pulse?before=2024-09-02"
      )

      expect(payload[:older_url]).to eq("/me/pulse?before=2024-09-02")
      expect(payload[:labels]).to eq(
        intensity: "Intensité",
        in_period: "Dans la période",
        history: "Hors période"
      )
    end

    it "flags no peak when the selected period only holds rest weeks" do
      intensity = intensity_for([
        rows.first.merge(period: Date.new(2026, 9, 7), workouts: 1, distance: 5_000.0, duration: 1800),
        rows.last.merge(workouts: 0, distance: 0.0, duration: 0, ascent: 0.0)
      ])

      payload = helper.pulse_chart_payload(
        intensity,
        period_range: Date.new(2026, 9, 14)..Date.new(2026, 9, 16),
        points: intensity.rows
      )

      expect(payload[:points].map { |point| point[:peak] }).to eq([ false, false ])
    end
  end

  describe "#pulse_detail" do
    it "speaks the sport count only from two sports" do
      row = { workouts: 1, distance: 10_000.0, duration: 3600, ascent: 120.0, rest: false }

      expect(helper.pulse_detail(row.merge(sports: 1))).not_to include("sport")
      expect(helper.pulse_detail(row.merge(sports: 3))).to include("3 sports")
    end
  end

  describe "#pulse_peak_label" do
    it "names the week, with the year when it is not the current one" do
      helper.instance_variable_set(:@today, Date.new(2026, 9, 16))

      expect(helper.pulse_peak_label(period: Date.new(2026, 9, 14))).to eq("semaine du 14 septembre")
      expect(helper.pulse_peak_label(period: Date.new(2025, 9, 8))).to eq("semaine du 8 septembre 2025")
    end
  end

  describe "#pulse_hint" do
    before do
      helper.instance_variable_set(:@today, Date.new(2026, 9, 22))
      helper.instance_variable_set(:@pulse_rows, [
        { period: Date.new(2024, 3, 4) },
        { period: Date.new(2026, 9, 21) }
      ])
    end

    it "names the weekly grain, the whole history, the scoring and the comparison" do
      helper.instance_variable_set(:@period, "days30")

      hint = helper.pulse_hint

      expect(hint).to include("Chaque capsule est une semaine", "du 4 mars 2024 à aujourd'hui")
      expect(hint).to include("temps, distance et dénivelé à parts égales")
      expect(hint).to include("30 jours précédents")
    end

    it "keeps the weekly grain over the whole history for every period" do
      helper.instance_variable_set(:@period, "week")
      expect(helper.pulse_hint).to include("semaine précédente")

      helper.instance_variable_set(:@period, "year")
      expect(helper.pulse_hint).to include("même période l'année dernière")

      helper.instance_variable_set(:@period, "all")
      expect(helper.pulse_hint).to include("totaux depuis le début")
    end

    it "collapses a one-week history onto a single week" do
      helper.instance_variable_set(:@period, "all")
      helper.instance_variable_set(:@pulse_rows, [ { period: Date.new(2026, 9, 21) } ])

      expect(helper.pulse_hint).to include("la semaine du 21 septembre 2026")
    end
  end

  describe "#sport_mix_payload" do
    it "names the sports, flags the others slice and carries every metric" do
      sport = build(:sport, slug: "running", label: "Running")
      mix = {
        slices: [ { sport:, values: { workouts: 2, distance: 10_000.0, duration: 3600, ascent: 50.0 } } ],
        others: { values: { workouts: 1, distance: 1000.0, duration: 600, ascent: 5.0 } }
      }

      helper.instance_variable_set(:@period, "days30")
      sport.id = 42
      payload = helper.sport_mix_payload(mix)

      expect(payload[:slices].first).to include(name: I18n.t("sports.running"), others: false)
      expect(payload[:slices].first[:url]).to eq(me_path(period: "days30", sport_id: 42))
      expect(payload[:slices].first[:open_label]).to eq("Filtrer sur #{I18n.t('sports.running')}")
      expect(payload[:slices].last).to include(name: I18n.t("me.mix.others"), others: true, url: nil)
      expect(payload[:slices].first[:values][:distance]).to eq(10_000.0)
    end
  end
end
