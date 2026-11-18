# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §3: the facts a summary is written from. Pure: every example
# feeds a context hash, never the database.
RSpec.describe Allure::Insights::Facts do
  def base_context
    {
      account: { unit_system: "metric", time_zone: "Europe/Paris", week_start: "monday" },
      units: Workouts::ContextPayload::UNITS,
      workout: {
        id: "wrk", title: "Le tour du lac", sport: "cycling_road",
        started_at: "2026-11-17T08:00:00Z", local_start: "2026-11-17T09:00:00+01:00",
        elapsed_time: 9_000, moving_time: 8_700, distance: 62_400.0, ascent: 850.0,
        average_speed: 7.17, average_pace: 139, average_heart_rate: 148, max_heart_rate: 172,
        origin: "import", places: [], weather: nil, heart_rate: nil,
        sport_details: { slug: "cycling_road", name: "Road cycling", family: "ride", virtual: false,
                         pace_basis_metres: 1_000, pace_speed_display: "speed" }
      },
      equipment: [],
      records_set: { records: [], best_effort_records: [] },
      laps: { recorded: [], detected: {}, truncated_sources: [] },
      splits: { distance: 5_000, rows: [], truncated: false },
      best_efforts: [],
      segment_efforts: [],
      training: {
        window_days: 28,
        same_sport: { workouts: 10, distance: 500_000.0, moving_time: 20_000, elapsed_time: 21_000, ascent: 5_000 },
        all_sports: { workouts: 12, distance: 600_000.0, moving_time: 25_000, elapsed_time: 26_000, ascent: 6_000 },
        recent_same_sport: []
      }
    }
  end

  def build(context = base_context, locale: "fr")
    described_class.build(context, locale:)
  end

  def fact(facts, id) = facts.find { it.id == id }

  describe "the baseline" do
    it "states the date, the sport, the distance, the time, the ascent and the average" do
      facts = build

      expect(fact(facts, "baseline:date").display).to eq("17 novembre 2026")
      expect(fact(facts, "baseline:sport").display).to eq("Vélo route")
      expect(fact(facts, "baseline:distance")).to have_attributes(display: "62,4 km", value: 62_400.0, unit: "m")
      expect(fact(facts, "baseline:moving_time").display).to eq("2 h 25 min")
      expect(fact(facts, "baseline:ascent").display).to eq("850 m")
      expect(fact(facts, "baseline:average").display).to eq("25,8 km/h")
    end

    it "prefers the pace for a sport that displays one" do
      context = base_context
      context[:workout][:sport_details].merge!(slug: "running", pace_speed_display: "pace")
      context[:workout][:average_pace] = 300
      context[:workout][:average_speed] = 3.33

      expect(fact(build(context), "baseline:average").display).to eq("5:00 /km")
    end

    it "drops a missing ascent and an empty average" do
      context = base_context
      context[:workout].merge!(ascent: 0.0, average_speed: nil, average_pace: nil)

      facts = build(context)

      expect(fact(facts, "baseline:ascent")).to be_nil
      expect(fact(facts, "baseline:average")).to be_nil
    end
  end

  describe "the records" do
    it "names a classic record and its value" do
      context = base_context
      context[:records_set][:records] = [
        { sport: "cycling_road", type: "FD", metric: "distance", value: 204_565.876 }
      ]

      expect(fact(build(context), "record:cycling_road:FD").display).to eq("Plus grande distance : 204,6 km")
    end

    it "states a personal best and a second best time" do
      context = base_context
      context[:best_efforts] = [
        { distance_key: "km10", elapsed_time: 2_492, personal_place: 1 },
        { distance_key: "km5", elapsed_time: 1_180, personal_place: 2 }
      ]
      facts = build(context)

      expect(fact(facts, "record:best_effort:km10").display).to eq("Meilleur temps sur 10 km : 41:32")
      expect(fact(facts, "record:best_effort:km5").display).to eq("2e meilleur temps sur 5 km : 19:40")
      expect(fact(facts, "record:best_effort:km10").weight).to be > fact(facts, "record:best_effort:km5").weight
    end
  end

  describe "the segments" do
    it "states a leaderboard podium" do
      context = base_context
      context[:segment_efforts] = [
        { segment: { id: "seg", name: "Le lac", kind: "segment" }, elapsed_time: 1_200, personal_place: nil,
          leaderboard: { rank: 1, participants: 42 } }
      ]

      expect(fact(build(context), "segment:rank:seg").display)
        .to eq("1er du classement sur Le lac (42 participants)")
    end

    it "states a personal place when the athlete is not on the podium" do
      context = base_context
      context[:segment_efforts] = [
        { segment: { id: "seg", name: "Le lac", kind: "segment" }, elapsed_time: 1_200, personal_place: 2,
          leaderboard: { rank: 17, participants: 42 } }
      ]

      expect(fact(build(context), "segment:best:seg").display).to eq("2e meilleur temps sur Le lac : 20:00")
      expect(fact(build(context), "segment:rank:seg")).to be_nil
    end

    it "does not call a podium an achievement on a segment with one participant" do
      context = base_context
      context[:segment_efforts] = [
        { segment: { id: "seg", name: "Le lac", kind: "segment" }, elapsed_time: 1_200, personal_place: nil,
          leaderboard: { rank: 1, participants: 1 } }
      ]

      expect(fact(build(context), "segment:rank:seg")).to be_nil
    end

    it "compares with the previous attempt on the same segment" do
      context = base_context
      context[:segment_efforts] = [
        { segment: { id: "seg", name: "Le lac", kind: "segment" }, elapsed_time: 1_200, personal_place: nil,
          leaderboard: {}, own_history: { previous_attempt: { elapsed_time: 1_212 } } }
      ]

      expect(fact(build(context), "comparison:seg").display)
        .to eq("12 s plus rapide que votre dernière fois sur Le lac")
    end
  end

  describe "the 28 days before" do
    it "states the volume and the ratio to the average workout" do
      context = base_context
      context[:workout][:distance] = 80_000.0

      facts = build(context)

      expect(fact(facts, "training:ratio").display).to eq("1,6 fois votre activité moyenne sur 28 jours (50,0 km)")
      expect(fact(facts, "training:volume").display).to eq("10 activités, 500,0 km sur 28 jours")
    end

    it "writes nothing without enough history" do
      context = base_context
      context[:training][:same_sport] = { workouts: 1, distance: 0.0 }

      expect(build(context).select { it.kind == "training" }).to be_empty
    end
  end

  describe "the pace over the splits" do
    it "states the negative split and the best split" do
      context = base_context
      context[:splits][:rows] = [
        { number: 1, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 2, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 3, distance: 5_000.0, elapsed_time: 1_100 },
        { number: 4, distance: 5_000.0, elapsed_time: 1_100 }
      ]

      facts = build(context)

      expect(fact(facts, "pacing:halves").display).to eq("Seconde moitié 20 s plus rapide que la première")
      expect(fact(facts, "pacing:best_split").display).to eq("Meilleur 5,0 km : 18:20")
    end

    it "ignores the trailing partial split" do
      context = base_context
      context[:splits][:rows] = [
        { number: 1, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 2, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 3, distance: 800.0, elapsed_time: 100, partial: true }
      ]

      expect(fact(build(context), "pacing:halves")).to be_nil
    end
  end

  describe "the heart rate" do
    it "states the average, the maximum and the dominant zone" do
      context = base_context
      context[:workout][:heart_rate] = { zones: [ 300, 1_200, 1_800, 600, 0 ] }

      facts = build(context)

      expect(fact(facts, "heart_rate:average").display).to eq("148 bpm de moyenne, 172 au maximum")
      expect(fact(facts, "heart_rate:zone").display).to eq("46 % du temps en zone 3")
    end

    it "states a cardiac drift from the series" do
      context = base_context
      context[:series] = Array.new(50) { { heart_rate: 140 } } + Array.new(50) { { heart_rate: 150 } }

      expect(fact(build(context), "heart_rate:drift").display)
        .to eq("Fréquence cardiaque en hausse de 7 % sur la seconde moitié")
    end

    it "invents no drift without a series" do
      expect(fact(build, "heart_rate:drift")).to be_nil
    end
  end

  describe "the weather" do
    it "states the wind exposure and the temperature" do
      context = base_context
      context[:workout][:weather] = {
        status: "ready",
        summary: { condition: "partly_cloudy", temperature_min: 7.7, temperature_max: 15.5,
                   apparent_temperature: 11.7, wind_exposure: { head: 0.42, tail: 0.21, cross: 0.37 } }
      }

      facts = build(context)

      expect(fact(facts, "weather:wind").display).to eq("Vent de face sur 42 % du parcours, de dos sur 21 %")
      expect(fact(facts, "weather:wind").sentiment).to eq(:bad)
      expect(fact(facts, "weather:temperature").display)
        .to eq("8–16 °C, Partiellement nuageux, ressenti 12 °C")
    end

    it "ignores a weather row that is not ready" do
      context = base_context
      context[:workout][:weather] = { status: "failed", summary: { temperature_min: 7.7 } }

      expect(build(context).select { it.kind == "weather" }).to be_empty
    end
  end

  describe "the detected sections" do
    it "states the biggest climb and the fast intervals" do
      context = base_context
      context[:laps][:detected] = {
        "climb" => [ { number: 1, name: "Route de Goncelin", distance: 4_407.5, ascent: 204.1, average_grade: 4.64 } ],
        "speed_interval" => [
          { number: 1, distance: 2_100.0, average_speed: 10.6 },
          { number: 2, distance: 900.0, average_speed: 9.0 },
          { number: 3, distance: 1_200.0, average_speed: 9.5 }
        ]
      }

      facts = build(context)

      expect(fact(facts, "climb:1").display).to eq("Route de Goncelin : 4,4 km à 4,6 %")
      expect(fact(facts, "interval:speed").display).to eq("3 efforts rapides, le plus long 2,1 km à 38,2 km/h")
    end
  end

  describe "the selection" do
    it "keeps every baseline and at most three facts of a kind" do
      context = base_context
      context[:records_set][:records] = [
        { sport: "cycling_road", type: "FD", metric: "distance", value: 204_565.876 },
        { sport: "cycling_road", type: "HA", metric: "ascent", value: 2_068 },
        { sport: "cycling_road", type: "LD", metric: "moving_time", value: 27_298 },
        { sport: "cycling_road", type: "MS", metric: "max_speed", value: 18.3 }
      ]

      facts = build(context)

      expect(facts.size).to be <= 16
      expect(facts.count { it.kind == "record" }).to eq(3)
      expect(facts.select { it.kind == "baseline" }.size).to eq(6)
    end

    it "orders the selected facts by weight" do
      weights = build.map(&:weight)

      expect(weights).to eq(weights.sort.reverse)
    end
  end

  describe "the digest" do
    it "is stable for the same facts and moves with the locale or the units" do
      facts = build
      first = described_class.digest(facts, version: 1, locale: "fr", unit_system: "metric")

      expect(described_class.digest(facts, version: 1, locale: "fr", unit_system: "metric")).to eq(first)
      expect(described_class.digest(facts, version: 1, locale: "en", unit_system: "metric")).not_to eq(first)
      expect(described_class.digest(facts, version: 1, locale: "fr", unit_system: "imperial")).not_to eq(first)
      expect(described_class.digest(facts, version: 2, locale: "fr", unit_system: "metric")).not_to eq(first)
    end
  end
end
