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

    it "keeps the imperial standard distances out of a metric member's facts" do
      context = base_context
      context[:best_efforts] = [
        { distance_key: "km10", elapsed_time: 2_492, personal_place: 1 },
        { distance_key: "mi5", elapsed_time: 1_464, personal_place: 1 }
      ]
      facts = build(context)

      expect(fact(facts, "record:best_effort:km10")).not_to be_nil
      expect(fact(facts, "record:best_effort:mi5")).to be_nil
    end

    it "keeps both vocabularies for an imperial member" do
      context = base_context
      context[:account][:unit_system] = "imperial"
      context[:best_efforts] = [ { distance_key: "mi5", elapsed_time: 1_464, personal_place: 1 } ]

      expect(fact(build(context), "record:best_effort:mi5")).not_to be_nil
    end

    it "drops a pace record on a sport that reads in speed" do
      context = base_context
      context[:records_set][:records] = [
        { sport: "cycling_road", type: "AP", metric: "average_pace", value: 122 },
        { sport: "cycling_road", type: "AS", metric: "average_speed", value: 7.17 }
      ]
      facts = build(context)

      expect(fact(facts, "record:cycling_road:AS")).not_to be_nil
      expect(fact(facts, "record:cycling_road:AP")).to be_nil
    end

    it "drops a speed record on a sport that reads in pace" do
      context = base_context
      context[:workout][:sport_details].merge!(slug: "running", pace_speed_display: "pace")
      context[:records_set][:records] = [
        { sport: "running", type: "AP", metric: "average_pace", value: 300 },
        { sport: "running", type: "AS", metric: "average_speed", value: 3.33 }
      ]
      facts = build(context)

      expect(fact(facts, "record:running:AP")).not_to be_nil
      expect(fact(facts, "record:running:AS")).to be_nil
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

    it "compares with the athlete's median once the segment is familiar" do
      context = base_context
      context[:segment_efforts] = [
        { segment: { id: "seg", name: "Le lac", kind: "segment" }, elapsed_time: 1_200, personal_place: nil,
          leaderboard: {}, own_history: { attempts: 12, median_time: 1_218 } }
      ]

      expect(fact(build(context), "segment:median:seg").display)
        .to eq("18 s sous votre temps médian sur Le lac (12 passages)")
    end

    it "keeps quiet on a segment ridden fewer than five times" do
      context = base_context
      context[:segment_efforts] = [
        { segment: { id: "seg", name: "Le lac", kind: "segment" }, elapsed_time: 1_200, personal_place: nil,
          leaderboard: {}, own_history: { attempts: 3, median_time: 1_218 } }
      ]

      expect(fact(build(context), "segment:median:seg")).to be_nil
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

  describe "the year before" do
    def row(started_at:, distance:, moving_time:, ascent: 0.0, average_speed: nil,
            average_heart_rate: nil, places: [])
      { local_start: started_at, started_at:, distance:, moving_time:, ascent:, average_speed:,
        average_heart_rate:, places: }
    end

    def with_history(context, rows, older: false, previous: 30, year_distance: 0.0, places: {},
                     last_same_sport_at: :from_rows)
      default_last = rows.map { it[:started_at] }.max
      last = last_same_sport_at == :from_rows ? default_last : last_same_sport_at
      context[:history] = {
        window_days: 365, same_sport: rows, older_same_sport: older, previous_workouts: previous,
        last_same_sport_at: last,
        year_to_date: { workouts: 10, distance: year_distance, moving_time: 0, elapsed_time: 0, ascent: 0 },
        places:
      }
      context
    end

    # Five outings of the sport in the year — four longer ones, then a recent
    # short one — so a "since" fact is about a habit, not a single ride, and
    # the latest outing is recent enough for the gap not to take the floor.
    def habit_rows(distance: 65_000.0, speed: 8.0, ascent: 0.0)
      past = %w[2026-06-01 2026-06-15 2026-07-01 2026-08-01].each_with_index.map do |day, index|
        row(started_at: "#{day}T08:00:00Z", distance: index.zero? ? distance - 5_000 : distance,
            moving_time: 8_400, ascent:, average_speed: speed)
      end
      past + [ row(started_at: "2026-10-20T08:00:00Z", distance: 30_000.0, moving_time: 4_200,
                   average_speed: speed) ]
    end

    it "states the pace against the usual one over a comparable distance" do
      context = base_context
      context[:workout][:sport_details][:pace_speed_display] = "pace"
      context[:workout][:average_speed] = 3.33
      context[:workout][:average_pace] = 300
      with_history(context, [
        row(started_at: "2026-10-01T08:00:00Z", distance: 60_000.0, moving_time: 9_000, average_speed: 3.0),
        row(started_at: "2026-10-08T08:00:00Z", distance: 61_000.0, moving_time: 9_000, average_speed: 3.0),
        row(started_at: "2026-10-15T08:00:00Z", distance: 59_000.0, moving_time: 9_000, average_speed: 3.0),
        row(started_at: "2026-10-22T08:00:00Z", distance: 60_000.0, moving_time: 9_000, average_speed: 3.0)
      ])

      fact = fact(build(context), "history:pace")

      expect(fact.display).to eq("33 s /km plus rapide que votre allure habituelle sur cette distance (5:33 /km)")
      expect(fact.sentiment).to eq(:good)
      expect(fact.weight).to eq(70)
    end

    it "uses the speed for a sport that displays one, and stays neutral when slower" do
      context = base_context
      with_history(context, Array.new(4) {
        row(started_at: "2026-10-01T08:00:00Z", distance: 60_000.0, moving_time: 9_000, average_speed: 8.0)
      })

      fact = fact(build(context), "history:pace")

      expect(fact.display).to eq("3,0 km/h moins vite que votre vitesse habituelle sur cette distance (28,8 km/h)")
      expect(fact.sentiment).to eq(:neutral)
      expect(fact.weight).to eq(48)
    end

    it "states the same pace for less heart" do
      context = base_context
      with_history(context, Array.new(3) {
        row(started_at: "2026-10-01T08:00:00Z", distance: 60_000.0, moving_time: 9_000,
            average_speed: 7.17, average_heart_rate: 160)
      })

      fact = fact(build(context), "history:effort_hr")

      expect(fact.display).to eq("Même allure, 12 bpm de moins que d'ordinaire")
      expect(fact.weight).to eq(72)
    end

    it "states the longest workout since a date" do
      context = base_context
      with_history(context, habit_rows + [
        row(started_at: "2026-11-01T08:00:00Z", distance: 40_000.0, moving_time: 6_000)
      ])

      expect(fact(build(context), "history:longest_since").display)
        .to eq("Votre plus longue sortie depuis le 1 août 2026")
    end

    it "says more than a year when the year holds nothing comparable but older outings exist" do
      context = with_history(base_context, habit_rows(distance: 10_000.0), older: true)

      expect(fact(build(context), "history:longest_since").display)
        .to eq("Votre plus longue sortie depuis plus d'un an")
    end

    it "keeps quiet about a habit the year does not hold" do
      context = with_history(base_context, [ row(started_at: "2026-11-01T08:00:00Z", distance: 40_000.0,
                                                   moving_time: 6_000) ], older: true)

      expect(fact(build(context), "history:longest_since")).to be_nil
      expect(fact(build(context), "history:fastest_since")).to be_nil
    end

    it "lets the gap speak alone after a long break" do
      context = with_history(base_context, habit_rows, older: true,
                                                      last_same_sport_at: "2026-04-01T08:00:00Z")

      facts = build(context)

      expect(facts.select { it.id.in?(%w[history:longest_since history:climb_since history:fastest_since]) })
        .to be_empty
      expect(fact(facts, "history:gap")).not_to be_nil
    end

    it "stays quiet when a record already says it" do
      context = base_context
      context[:records_set][:records] = [
        { sport: "cycling_road", type: "FD", metric: "distance", value: 204_565.876 }
      ]
      with_history(context, habit_rows)

      expect(fact(build(context), "history:longest_since")).to be_nil
    end

    it "states the fastest outing since a date, from comparable outings only" do
      context = base_context
      with_history(context, habit_rows)

      expect(fact(build(context), "history:fastest_since").display)
        .to eq("Votre vitesse moyenne la plus élevée depuis le 1 août 2026")
    end

    it "speaks of pace for a sport that displays one" do
      context = base_context
      context[:workout][:sport_details].merge!(slug: "running", pace_speed_display: "pace")
      context[:workout][:average_speed] = 3.33
      context[:workout][:average_pace] = 300
      with_history(context, habit_rows(speed: 4.0))

      expect(fact(build(context), "history:fastest_since").display)
        .to eq("Votre allure la plus rapide depuis le 1 août 2026")
    end

    it "asks for three comparable outings before calling a pace the fastest" do
      context = base_context
      with_history(context, habit_rows.first(2) + [
        row(started_at: "2026-10-01T08:00:00Z", distance: 20_000.0, moving_time: 3_000, average_speed: 8.0),
        row(started_at: "2026-10-02T08:00:00Z", distance: 20_000.0, moving_time: 3_000, average_speed: 8.0),
        row(started_at: "2026-10-03T08:00:00Z", distance: 20_000.0, moving_time: 3_000, average_speed: 8.0)
      ])

      expect(fact(build(context), "history:fastest_since")).to be_nil
    end

    it "compares with the closest comparable outing on the pace" do
      context = base_context
      with_history(context, [
        row(started_at: "2026-10-02T08:00:00Z", distance: 62_000.0, moving_time: 9_000, ascent: 800.0,
            average_speed: 7.9)
      ])

      expect(fact(build(context), "history:similar").display)
        .to eq("Sortie comparable du 2 octobre 2026 (62,0 km, 800 m) : 2,6 km/h moins vite")
    end

    it "stays quiet when the comparable outing held the same pace, whatever the clock says" do
      context = base_context
      with_history(context, [
        row(started_at: "2026-10-02T08:00:00Z", distance: 62_000.0, moving_time: 12_000, ascent: 800.0,
            average_speed: 7.17)
      ])

      expect(fact(build(context), "history:similar")).to be_nil
    end

    it "prefers the comparable outing that shares a place" do
      context = base_context
      context[:workout][:places] = [ { "name" => "Chevreuse" } ]
      with_history(context, [
        row(started_at: "2026-09-01T08:00:00Z", distance: 62_000.0, moving_time: 9_000, ascent: 800.0,
            average_speed: 8.0),
        row(started_at: "2026-08-25T08:00:00Z", distance: 62_000.0, moving_time: 9_000, ascent: 800.0,
            average_speed: 8.0, places: [ "Chevreuse" ])
      ])

      expect(fact(build(context), "history:similar").display).to start_with("Sortie comparable du 25 août 2026")
    end

    it "states the gap since the last workout of the sport, typed sessions included" do
      context = base_context
      with_history(context, [], last_same_sport_at: "2026-10-25T08:00:00Z")

      expect(fact(build(context), "history:gap").display)
        .to eq("Vélo route : première activité depuis 23 jours")
    end

    it "says nothing about a gap on the very first workout of a sport" do
      context = with_history(base_context, [], last_same_sport_at: nil)

      expect(fact(build(context), "history:gap")).to be_nil
    end

    it "states a round year total the workout crossed" do
      context = base_context
      with_history(context, [], year_distance: 450_000.0)

      expect(fact(build(context), "history:year_total").display).to eq("Ça porte l'année à 500 km (Vélo route)")
    end

    it "crosses the round figures of the member's own units" do
      context = base_context
      context[:account][:unit_system] = "imperial"
      with_history(context, [], year_distance: 950_000.0)

      expect(fact(build(context, locale: "en"), "history:year_total").display)
        .to eq("That brings the year to 600 mi (Road cycling)")
    end

    it "writes nothing without a history section" do
      expect(build.select { it.kind == "history" }).to be_empty
    end
  end

  describe "the places" do
    def with_places(context, places:, history_places: {}, previous: 30)
      context[:workout][:places] = places.map { { "name" => it } }
      context[:history] = {
        window_days: 365, same_sport: [], older_same_sport: false, previous_workouts: previous,
        year_to_date: { workouts: 10, distance: 0.0, moving_time: 0, elapsed_time: 0, ascent: 0 },
        places: history_places
      }
      context
    end

    it "names the route and a place visited more than five times this year" do
      context = with_places(base_context, places: %w[Chevreuse Cernay],
                            history_places: { "Chevreuse" => { seen_before: true, year_count: 8 },
                                              "Cernay" => { seen_before: true, year_count: 1 } })

      facts = build(context)

      expect(fact(facts, "place:route").display).to eq("Par Chevreuse, Cernay")
      expect(fact(facts, "place:regular:0").display).to eq("Chevreuse : 9 activités cette année")
      expect(fact(facts, "place:first:0")).to be_nil
    end

    it "states a first visit once the account has a history, below the notable threshold" do
      context = with_places(base_context, places: [ "Cernay" ],
                            history_places: { "Cernay" => { seen_before: false, year_count: 0 } })

      visit = fact(build(context), "place:first:0")

      expect(visit.display).to eq("Nouveau lieu : Cernay")
      expect(visit.weight).to eq(64)
      expect(described_class.notable([ visit ])).to be_empty
    end

    it "does not call everything a first visit on a new account" do
      context = with_places(base_context, places: [ "Cernay" ],
                            history_places: { "Cernay" => { seen_before: false, year_count: 0 } }, previous: 5)

      expect(fact(build(context), "place:first:0")).to be_nil
    end

    it "reduces a virtual workout to its world" do
      context = base_context
      context[:workout][:sport_details].merge!(slug: "cycling_virtual", virtual: true)
      context[:workout][:places] = [ { "name" => "Watopia" } ]
      with_places(context, places: [ "Watopia" ],
                           history_places: { "Watopia" => { seen_before: false, year_count: 0 } })

      facts = build(context)

      expect(fact(facts, "place:venue").display).to eq("Monde : Watopia")
      expect(facts.count { it.kind == "place" }).to eq(1)
    end

    it "writes nothing without a place" do
      expect(build.select { it.kind == "place" }).to be_empty
    end
  end

  describe "the 28 days before" do
    it "states the volume and the ratio to the average workout" do
      context = base_context
      context[:workout][:distance] = 80_000.0

      facts = build(context)

      expect(fact(facts, "training:ratio").display).to eq("1,6 fois votre activité moyenne sur 28 jours (50,0 km)")
      expect(fact(facts, "training:volume").display).to eq("500,0 km sur 10 activités en 28 jours")
    end

    it "writes nothing without enough history" do
      context = base_context
      context[:training][:same_sport] = { workouts: 1, distance: 0.0 }

      expect(build(context).select { it.kind == "training" }).to be_empty
    end
  end

  describe "the best split" do
    it "states the fastest split and ignores the trailing partial one" do
      context = base_context
      context[:splits][:rows] = [
        { number: 1, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 2, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 3, distance: 5_000.0, elapsed_time: 1_100 },
        { number: 4, distance: 800.0, elapsed_time: 100, partial: true }
      ]

      expect(fact(build(context), "pacing:best_split").display).to eq("Meilleur 5,0 km : 18:20")
    end

    it "writes nothing with fewer than three full splits" do
      context = base_context
      context[:splits][:rows] = [
        { number: 1, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 2, distance: 5_000.0, elapsed_time: 1_200 },
        { number: 3, distance: 800.0, elapsed_time: 100, partial: true }
      ]

      expect(fact(build(context), "pacing:best_split")).to be_nil
    end
  end

  describe "the course" do
    def course_slot(from:, to:, terrain:, name: nil, number: 1, height: 0.0, grade: nil)
      Allure::Insights::CoursePlan::Slot.new(start_distance: from, end_distance: to, terrain:, name:, number:,
                                             height:, grade:)
    end

    def course_section(distance:, moving_time:, ascent: 0.0, descent: 0.0, start_distance: 0.0,
                       elevation_distance: nil, grade_adjusted_distance: 0.0, grade_adjusted_time: 0.0,
                       heart_rate: nil)
      Allure::Gpx::RouteProfile::Section.new(
        start_distance:, end_distance: start_distance + distance, distance:, moving_time:, ascent:, descent:,
        elevation_distance: elevation_distance || distance,
        grade_adjusted_distance:, grade_adjusted_time:,
        heart_rate_time: heart_rate ? moving_time.to_f : 0.0,
        heart_rate_sum: heart_rate ? heart_rate * moving_time.to_f : 0.0
      )
    end

    def course(sections, slots, mode: :terrain)
      plan = Allure::Insights::CoursePlan::Plan.new(mode:, slots:)
      result = Allure::Gpx::RouteProfile::Result.new(distance: sections.sum(&:distance), sections:)
      Allure::Insights::Course.new(plan:, result:)
    end

    def part_slots(sections)
      sections.map do |section|
        course_slot(from: section.start_distance, to: section.end_distance, terrain: "part")
      end
    end

    def pace_context
      context = base_context
      context[:workout][:sport_details][:pace_speed_display] = "pace"
      context[:workout][:sport_details][:pace_basis_metres] = 1_000
      context[:workout][:average_speed] = 2.5
      context[:workout][:average_pace] = 400
      context[:workout][:ascent] = 240.0
      context
    end

    it "writes each section from the start, with its terrain, its pace and its heart rate" do
      context = pace_context
      climb = course_section(distance: 4_000, moving_time: 1_600, ascent: 240, heart_rate: 152)
      flat = course_section(distance: 6_000, moving_time: 2_400, start_distance: 4_000)
      context[:course] = course([ climb, flat ], [
        course_slot(from: 0, to: 4_000, terrain: "climb", name: "Col", height: 240, grade: 6.0),
        course_slot(from: 4_000, to: 10_000, terrain: "between")
      ])

      facts = build(context)

      expect(fact(facts, "section:1").display)
        .to eq("de 0 m à 4,0 km · montée « Col », 4,0 km à 6,0 %, 240 m · 6:40 /km · 152 bpm")
      expect(fact(facts, "section:2").display).to eq("de 4,0 km à 10,0 km · plat · 6:40 /km")
      expect(fact(facts, "section:1")).to have_attributes(kind: "section", weight: 0)
    end

    it "reads a section between two climbs as flat or rolling from its measured terrain" do
      context = pace_context
      flat = course_section(distance: 4_000, moving_time: 1_600)
      rolling = course_section(distance: 4_000, moving_time: 1_600, start_distance: 4_000, ascent: 200, descent: 200)
      context[:course] = course([ flat, rolling ], [
        course_slot(from: 0, to: 4_000, terrain: "between"),
        course_slot(from: 4_000, to: 8_000, terrain: "between")
      ])

      facts = build(context)

      expect(fact(facts, "section:1").display).to include("· plat ·")
      expect(fact(facts, "section:2").display).to include("· vallonné ·")
    end

    it "compares a section with the workout's own average, but never a descent" do
      context = pace_context
      fast = course_section(distance: 4_000, moving_time: 1_200)
      descent = course_section(distance: 6_000, moving_time: 2_400, start_distance: 4_000, descent: 300)
      context[:course] = course([ fast, descent ], [
        course_slot(from: 0, to: 4_000, terrain: "between"),
        course_slot(from: 4_000, to: 10_000, terrain: "descent")
      ])

      facts = build(context)

      expect(fact(facts, "section:1").display).to include("33 % plus vite que votre moyenne")
      expect(fact(facts, "section:2").display).not_to include("votre moyenne")
    end

    it "gives a climb its flat-equivalent pace" do
      context = pace_context
      climb = course_section(distance: 4_000, moving_time: 1_600, ascent: 240,
                             grade_adjusted_distance: 4_000, grade_adjusted_time: 1_440)
      context[:course] = course([ climb ], [ course_slot(from: 0, to: 4_000, terrain: "climb", name: "Col",
                                                        height: 240) ])

      expect(fact(build(context), "section:1").display).to include("6:00 /km à plat équivalent")
    end

    it "keeps the sections out of the selection and the highlight" do
      context = pace_context
      section = course_section(distance: 4_000, moving_time: 1_600)
      context[:course] = course([ section ], [ course_slot(from: 0, to: 4_000, terrain: "climb") ])

      facts = build(context)

      expect(described_class.notable(facts)).to be_empty
      expect(described_class.highlight(facts).kind).not_to eq("section")
    end

    it "says when the last section was the fastest" do
      context = pace_context
      sections = [
        course_section(distance: 3_000, moving_time: 1_200),
        course_section(distance: 3_000, moving_time: 1_200, start_distance: 3_000),
        course_section(distance: 3_000, moving_time: 1_100, start_distance: 6_000)
      ]
      context[:course] = course(sections, part_slots(sections), mode: :parts)

      item = fact(build(context), "course:finish")

      expect(item.display)
        .to eq("Fin de parcours plus rapide qu'au départ, à terrain égal : 6:07 /km contre 6:40 /km")
      expect(item).to have_attributes(kind: "course", sentiment: :good, weight: 70)
    end

    it "notes a slower finish on comparable ground" do
      context = pace_context
      sections = [
        course_section(distance: 3_000, moving_time: 1_150, heart_rate: 140),
        course_section(distance: 3_000, moving_time: 1_250, start_distance: 3_000, heart_rate: 150)
      ]
      context[:course] = course(sections, part_slots(sections), mode: :parts)

      item = fact(build(context), "course:fade")

      expect(item.display)
        .to eq("Plus lent en fin de parcours qu'au départ, à terrain égal : 6:57 /km contre 6:23 /km")
      expect(item).to have_attributes(sentiment: :neutral, weight: 62)
    end

    it "does not call it a fade when the heart rate came down" do
      context = pace_context
      sections = [
        course_section(distance: 3_000, moving_time: 1_150, heart_rate: 150),
        course_section(distance: 3_000, moving_time: 1_250, start_distance: 3_000, heart_rate: 130)
      ]
      context[:course] = course(sections, part_slots(sections), mode: :parts)

      expect(fact(build(context), "course:fade")).to be_nil
    end

    it "says when the climb was held at the flat pace" do
      context = pace_context
      sections = [
        course_section(distance: 4_000, moving_time: 1_440),
        course_section(distance: 4_000, moving_time: 1_600, start_distance: 4_000, ascent: 240,
                       grade_adjusted_distance: 4_000, grade_adjusted_time: 1_440),
        course_section(distance: 2_000, moving_time: 720, start_distance: 8_000)
      ]
      context[:course] = course(sections, [
        course_slot(from: 0, to: 4_000, terrain: "between"),
        course_slot(from: 4_000, to: 8_000, terrain: "climb", name: "Col", height: 240),
        course_slot(from: 8_000, to: 10_000, terrain: "between")
      ])

      item = fact(build(context), "course:climb_held")

      expect(item.display).to eq("Effort régulier dans Col : 6:00 /km à plat équivalent, 6:00 /km sur le plat")
      expect(item).to have_attributes(sentiment: :good, weight: 72)
    end

    it "says when the same pace cost more heart at the end" do
      context = pace_context
      sections = [
        course_section(distance: 4_000, moving_time: 1_600, heart_rate: 140),
        course_section(distance: 4_000, moving_time: 1_600, start_distance: 4_000, heart_rate: 150)
      ]
      context[:course] = course(sections, part_slots(sections), mode: :parts)

      expect(fact(build(context), "course:hr_flat").display)
        .to eq("Même allure en fin de parcours pour 10 bpm de plus")
    end

    it "says when most of the moving time was spent climbing" do
      context = pace_context
      sections = [
        course_section(distance: 4_000, moving_time: 2_000, ascent: 240),
        course_section(distance: 2_000, moving_time: 400, start_distance: 4_000),
        course_section(distance: 4_000, moving_time: 2_000, start_distance: 6_000, ascent: 240)
      ]
      context[:course] = course(sections, [
        course_slot(from: 0, to: 4_000, terrain: "climb", height: 240),
        course_slot(from: 4_000, to: 6_000, terrain: "between"),
        course_slot(from: 6_000, to: 10_000, terrain: "climb", height: 240)
      ])

      expect(fact(build(context), "course:climb_share").display).to eq("91 % du temps passé en montée")
    end

    it "writes no course fact without a course" do
      expect(build.select { it.kind == "course" || it.kind == "section" }).to be_empty
    end
  end

  describe "the heart rate" do
    it "states the average, the maximum and the dominant zone" do
      context = base_context
      context[:workout][:heart_rate] = {
        zones: [
          { zone: 1, lower_bpm: 90, upper_bpm: 110, seconds: 300 },
          { zone: 2, lower_bpm: 110, upper_bpm: 130, seconds: 1_200 },
          { zone: 3, lower_bpm: 130, upper_bpm: 150, seconds: 1_800 },
          { zone: 4, lower_bpm: 150, upper_bpm: 170, seconds: 600 },
          { zone: 5, lower_bpm: 170, upper_bpm: 190, seconds: 0 }
        ]
      }

      facts = build(context)

      expect(fact(facts, "heart_rate:average").display).to eq("148 bpm de moyenne, 172 au maximum")
      expect(fact(facts, "heart_rate:zone").display).to eq("46 % du temps en zone 3")
    end

    it "invents no drift without a series" do
      expect(fact(build, "heart_rate:drift")).to be_nil
    end

    it "drops the drift on a hilly route" do
      context = base_context
      context[:workout][:ascent] = 2_000.0
      context[:series] = Array.new(50) { { heart_rate: 140 } } + Array.new(50) { { heart_rate: 150 } }

      expect(fact(build(context), "heart_rate:drift")).to be_nil
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

      expect(facts.size).to be <= 18
      expect(facts.count { it.kind == "record" }).to eq(3)
      expect(facts.select { it.kind == "baseline" }.size).to eq(6)
    end

    it "orders the selected facts by weight" do
      weights = build.map(&:weight)

      expect(weights).to eq(weights.sort.reverse)
    end
  end

  describe "the narrative length" do
    def fact(id, kind, weight, sentiment: :good)
      Allure::Insights::Fact.new(id:, kind:, display: id, value: nil, unit: nil, direction: nil,
                                 sentiment:, weight:, source: "workout")
    end

    it "asks one sentence when only the baseline and a scene-setting place exist" do
      facts = [ fact("baseline:date", "baseline", 100), fact("place:route", "place", 45) ]

      expect(described_class.sentence_range(facts)).to eq(1..1)
      expect(described_class.notable(facts)).to be_empty
      expect(described_class.highlight(facts).id).to eq("place:route")
    end

    it "grows the range with the number of telling facts" do
      one = [ fact("record:a", "record", 92) ]
      two = %w[a b].map { |id| fact("record:#{id}", "record", 90) }
      four = %w[a b c d].map { |id| fact("record:#{id}", "record", 90) }
      six = %w[a b c d e f].map { |id| fact("record:#{id}", "record", 90) }

      expect(described_class.sentence_range(one)).to eq(1..1)
      expect(described_class.sentence_range(two)).to eq(1..2)
      expect(described_class.sentence_range(four)).to eq(2..3)
      expect(described_class.sentence_range(six)).to eq(3..5)
    end

    it "highlights the heaviest non-baseline fact, never a baseline" do
      facts = [ fact("baseline:distance", "baseline", 100), fact("training:volume", "training", 55),
                fact("record:fd", "record", 92) ]

      expect(described_class.highlight(facts).id).to eq("record:fd")
      expect(described_class.highlight([ fact("baseline:distance", "baseline", 100) ])).to be_nil
    end

    it "prefers a good or bad fact over a heavier neutral one" do
      neutral = Allure::Insights::Fact.new(id: "training:ratio", kind: "training", display: "0,5 fois",
                                           value: 0.5, unit: "ratio", direction: "down",
                                           sentiment: :neutral, weight: 72, source: "training")
      good = Allure::Insights::Fact.new(id: "record:fd", kind: "record", display: "204 km", value: 204_000.0,
                                        unit: "m", direction: "up", sentiment: :good, weight: 70,
                                        source: "records_set")

      expect(described_class.highlight([ neutral, good ]).id).to eq("record:fd")
    end

    it "never calls a neutral figure a story" do
      neutral = Allure::Insights::Fact.new(id: "training:ratio", kind: "training", display: "0,5 fois",
                                           value: 0.5, unit: "ratio", direction: "down",
                                           sentiment: :neutral, weight: 72, source: "training")
      good = Allure::Insights::Fact.new(id: "record:fd", kind: "record", display: "204 km", value: 204_000.0,
                                        unit: "m", direction: "up", sentiment: :good, weight: 70,
                                        source: "records_set")

      expect(described_class.notable([ neutral ])).to be_empty
      expect(described_class.notable([ good ]).size).to eq(1)
      expect(described_class.sentence_range([ neutral ])).to eq(1..1)
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
