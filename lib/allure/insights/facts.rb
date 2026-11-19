# frozen_string_literal: true

require "digest"
require "json"
require "time"

module Allure
  module Insights
    # The facts a summary is written from (docs/dev/AI.md §3). Pure: it reads the
    # owner-only context (`Workouts::ContextPayload`) plus an optional `:series`
    # and touches neither the database nor the network. Each detector emits zero
    # or more facts; the selection keeps the most telling ones.
    class Facts
      MAX_FACTS = 18
      PER_KIND = 3
      HISTORY_PER_KIND = 4
      # The weight from which a non-baseline fact is worth a sentence of its own
      # (AI.md §3.4). Below it, the summary says one quiet sentence and stops.
      NOTABLE_WEIGHT = 70
      # The history detectors' windows (AI.md §3.3), all relative to the
      # workout's own start so the facts stay deterministic.
      RECENT_DAYS = 90
      SINCE_DAYS = 60
      # A "since" fact only means something once the year holds enough outings
      # to be a habit, and never right after a long break, where only the gap
      # itself tells the story (AI.md §3.3).
      SINCE_MIN_ROWS = 5
      FASTEST_MIN_COMPARABLE = 3
      LONG_GAP_DAYS = 60
      GAP_DAYS = 14
      COMPARABLE_LOW = 0.6
      COMPARABLE_HIGH = 1.6
      SIMILAR_DISTANCE = 0.10
      SIMILAR_ASCENT = 0.25
      SIMILAR_ASCENT_FLOOR = 50.0
      FIRST_VISIT_FLOOR = 10
      REGULAR_PLACE_FLOOR = 4
      MIN_DISTANCE = 1_000.0
      MIN_ASCENT = 50.0
      # The route in sections (AI.md §3.3). The sections themselves are not
      # selected; the course facts built from them are, on ground that is
      # comparable: flat against flat, a climb at its flat-equivalent pace.
      SECTION_ELEVATION_COVERAGE = 0.9
      SECTION_AVERAGE_DELTA = 0.02
      SECTION_FLAT_METRES_PER_KM = 5.0
      COURSE_FINISH_DELTA = 0.03
      COURSE_FADE_DELTA = 0.05
      COURSE_PACE_MATCH = 0.03
      COURSE_HEART_RATE_DELTA = 0.05
      COURSE_CLIMB_HELD = 0.03
      COURSE_CLIMB_SHARE = 0.40
      # The standard distances of the other measurement family are not part of
      # this member's vocabulary (AI.md §3.3).
      IMPERIAL_EFFORTS = /\A(?:mi\d+|half_mile)\z/
      PACE_METRICS = %w[average_pace best_pace].freeze
      SPEED_METRICS = %w[average_speed max_speed].freeze
      KINDS = %w[baseline record segment comparison training history place course pacing heart_rate weather
                 climb interval section].freeze
      # The context section each kind reads, unless a detector overrides it.
      SOURCES = {
        "baseline" => "workout", "record" => "records_set", "segment" => "segment_efforts",
        "comparison" => "segment_efforts", "training" => "training", "history" => "history",
        "place" => "history", "course" => "course", "pacing" => "splits", "heart_rate" => "workout",
        "weather" => "workout", "climb" => "laps", "interval" => "laps", "section" => "course"
      }.freeze

      class << self
        def build(context, locale:)
          new(context, locale:).build
        end

        # The staleness key of a generated summary (AI.md §3.6): the version,
        # the locale, the units and the facts, canonicalized.
        def digest(facts, version:, locale:, unit_system:)
          payload = { version: version.to_i, locale: locale.to_s, unit_system: unit_system.to_s,
                      facts: facts.map(&:to_h) }
          Digest::SHA256.hexdigest(JSON.generate(payload))
        end

        # The non-baseline facts that carry a story (AI.md §3.4). A neutral
        # figure — a slower usual pace, a smaller week — never makes an outing
        # notable on its own; the route's sections are context by nature and
        # never count either.
        def notable(facts)
          facts.reject { it.kind == "baseline" || it.kind == "section" }
               .select { it.weight >= NOTABLE_WEIGHT && informative?(it) }
        end

        def informative?(fact) = fact.sentiment.to_s != "neutral"

        # How many sentences the answer may carry: a plain outing gets one, a
        # big one up to five, and the model is never asked to pad (AI.md §4.1).
        # A single telling fact is one sentence, not one fact plus a recap of
        # the dashboard.
        def sentence_range(facts)
          case notable(facts).size
          when 0, 1 then 1..1
          when 2 then 1..2
          when 3..4 then 2..3
          else 3..5
          end
        end

        # The fact the summary opens with: the most telling one, never a
        # baseline figure the member already reads on the page. A neutral fact
        # only opens when nothing else is left (AI.md §4.2); a route section is
        # never the subject.
        def highlight(facts)
          facts.reject { it.kind == "baseline" || it.kind == "section" }
               .min_by { |item| [ informative?(item) ? 0 : 1, -item.weight, KINDS.index(item.kind),
                                  item.id ] }
        end
      end

      def initialize(context, locale:)
        @context = context
        @locale = locale.to_sym
        @format = Format.new(locale: @locale, unit_system: context.dig(:account, :unit_system) || "metric")
      end

      # The selected facts, then the route's sections: the model reads the whole
      # course, but a section never competes for the 18 selected slots and never
      # lengthens the answer (AI.md §3.4).
      def build
        selected(
          baseline_facts + record_facts + segment_facts + comparison_facts + training_facts +
          history_facts + place_facts + course_facts + pacing_facts + heart_rate_facts + weather_facts +
          climb_facts + interval_facts
        ) + section_facts
      end

      private

      attr_reader :context, :locale, :format

      def workout = context.fetch(:workout)
      def sport = workout.fetch(:sport_details, {})

      def fact(id, kind, display, value: nil, unit: nil, direction: nil, sentiment: :neutral, weight: 50, source: nil)
        Fact.new(id:, kind:, display:, value:, unit:, direction:, sentiment:, weight:, source: source || SOURCES.fetch(kind))
      end

      def t(key, **options) = I18n.t(key, locale:, **options)

      # --- baseline ---------------------------------------------------------

      def baseline_facts
        facts = [
          fact("baseline:date", "baseline", format.date(local_start), weight: 100),
          fact("baseline:sport", "baseline", sport_name, weight: 100)
        ]
        facts << fact("baseline:distance", "baseline", format.distance(workout[:distance], precision: 1),
                      value: workout[:distance], unit: "m", weight: 100) if workout[:distance].to_f.positive?
        if workout[:moving_time].to_i.positive?
          facts << fact("baseline:moving_time", "baseline", format.duration_human(workout[:moving_time]),
                        value: workout[:moving_time], unit: "s", weight: 100)
        end
        if workout[:ascent].to_f.positive?
          facts << fact("baseline:ascent", "baseline", format.elevation(workout[:ascent]),
                        value: workout[:ascent], unit: "m", weight: 100)
        end
        average = average_fact
        facts << average if average
        facts
      end

      def average_fact
        if pace_display?
          pace = workout[:average_pace]
          pace && fact("baseline:average", "baseline", format.pace(pace, basis: pace_basis),
                       value: pace, unit: "s/#{pace_basis} m", weight: 100)
        else
          speed = workout[:average_speed]
          speed && fact("baseline:average", "baseline", format.speed(speed), value: speed, unit: "m/s", weight: 100)
        end
      end

      def pace_display? = sport[:pace_speed_display] != "speed"
      def pace_basis = sport[:pace_basis_metres] || 1_000

      def local_start
        value = workout[:local_start]
        value ? Time.iso8601(value) : Time.iso8601(workout.fetch(:started_at))
      end

      def sport_name = t("sports.#{sport[:slug]}", default: sport[:name].to_s)

      # --- records ----------------------------------------------------------

      def record_facts
        Array(context.dig(:records_set, :records)).filter_map { |record| record_fact(record) } +
          Array(context[:best_efforts]).filter_map { |effort| best_effort_fact(effort) }
      end

      def record_fact(record)
        return unless record_family?(record[:metric])

        formatted = format_record(record)
        return unless formatted

        label = t("records.types.#{record[:type].to_s.downcase}", default: record[:type].to_s)
        fact("record:#{record[:sport]}:#{record[:type]}", "record", "#{label} : #{formatted}",
             value: record[:value], unit: record[:metric], direction: "up", sentiment: :good, weight: 92)
      end

      # A pace record on a sport that reads in speed (a ride, a hike) says
      # nothing the member asked to see, and the reverse holds too.
      def record_family?(metric)
        metric = metric.to_s
        return true unless PACE_METRICS.include?(metric) || SPEED_METRICS.include?(metric)

        pace_display? ? PACE_METRICS.include?(metric) : SPEED_METRICS.include?(metric)
      end

      # A metric member does not think in miles: the other family's standard
      # distances stay out of the facts (AI.md §3.3).
      def other_measure?(distance_key)
        IMPERIAL_EFFORTS.match?(distance_key.to_s) && !imperial?
      end

      def format_record(record)
        case record[:metric].to_s
        when "distance" then format.distance(record[:value], precision: 1)
        when "ascent" then format.elevation(record[:value])
        when "moving_time" then format.duration_human(record[:value])
        when "average_pace", "best_pace" then format.pace(record[:value])
        when "average_speed", "max_speed" then format.speed(record[:value])
        end
      end

      def best_effort_fact(effort)
        place = effort[:personal_place]
        return unless place && place <= 3
        return if other_measure?(effort[:distance_key])

        label = t("records.distances.#{effort[:distance_key]}", default: effort[:distance_key].to_s)
        display = t("insights.facts.effort", place: t("insights.facts.places.#{place_word(place)}"), label:,
                                            time: format.duration(effort[:elapsed_time]))
        fact("record:best_effort:#{effort[:distance_key]}", "record", display, value: effort[:elapsed_time], unit: "s",
             direction: "up", sentiment: :good, weight: place == 1 ? 95 : 82, source: "best_efforts")
      end

      # --- segments and their comparison ------------------------------------

      def segment_facts
        Array(context[:segment_efforts]).flat_map do |effort|
          name = effort.dig(:segment, :name)
          next [] if name.blank?

          standing(effort, name) + segment_median_facts(effort, name)
        end
      end

      def standing(effort, name)
        rank = effort.dig(:leaderboard, :rank)
        place = effort[:personal_place]
        participants = effort.dig(:leaderboard, :participants).to_i
        if rank && rank <= 3 && participants >= 3
          display = t("insights.facts.rank", place: t("insights.facts.ranks.#{place_word(rank)}"), label: name,
                                            count: participants)
          [ fact("segment:rank:#{effort.dig(:segment, :id)}", "segment", display, value: rank, unit: "rank",
                 direction: "up", sentiment: :good, weight: 88) ]
        elsif place && place <= 3
          display = t("insights.facts.effort", place: t("insights.facts.places.#{place_word(place)}"), label: name,
                                              time: format.duration(effort[:elapsed_time]))
          [ fact("segment:best:#{effort.dig(:segment, :id)}", "segment", display, value: effort[:elapsed_time],
                 unit: "s", direction: "up", sentiment: :good, weight: place == 1 ? 90 : 80) ]
        else
          []
        end
      end

      # The effort against the athlete's own median on that segment, once they
      # have ridden it five times.
      def segment_median_facts(effort, name)
        history = effort[:own_history]
        return [] unless history.is_a?(Hash)

        median = history[:median_time]
        attempts = history[:attempts].to_i
        return [] unless median && attempts >= 5

        delta = median.to_i - effort[:elapsed_time].to_i
        return [] if delta.abs < 5

        key = delta.positive? ? "insights.facts.segment_median_faster" : "insights.facts.segment_median_slower"
        [ fact("segment:median:#{effort.dig(:segment, :id)}", "segment",
               t(key, delta: format.duration_span(delta.abs), label: name, count: attempts),
               value: delta, unit: "s", direction: delta.positive? ? "up" : "down",
               sentiment: delta.positive? ? :good : :neutral, weight: delta.positive? ? 62 : 45) ]
      end

      def comparison_facts
        Array(context[:segment_efforts]).filter_map do |effort|
          previous = effort.dig(:own_history, :previous_attempt)
          next unless previous

          delta = effort[:elapsed_time].to_i - previous[:elapsed_time].to_i
          next if delta.abs < 5

          name = effort.dig(:segment, :name)
          key = delta.negative? ? "insights.facts.faster" : "insights.facts.slower"
          display = t(key, delta: format.duration_span(delta.abs), label: name)
          fact("comparison:#{effort.dig(:segment, :id)}", "comparison", display, value: delta, unit: "s",
               direction: delta.negative? ? "up" : "down", sentiment: delta.negative? ? :good : :bad, weight: 74)
        end
      end

      # --- the 28 days before ----------------------------------------------

      def training_facts
        totals = context.dig(:training, :same_sport)
        return [] unless totals.is_a?(Hash)

        count = totals[:workouts].to_i
        distance = totals[:distance].to_f
        return [] if count < 2 || distance <= 0

        facts = []
        average = distance / count
        ratio = workout[:distance].to_f / average
        if ratio >= 1.3 || ratio <= 0.7
          facts << fact("training:ratio", "training",
                        t("insights.facts.average_ratio", ratio: format.decimal(ratio.round(1), precision: 1),
                                                         average: format.distance(average, precision: 1)),
                        value: ratio, unit: "ratio", direction: ratio >= 1.3 ? "up" : "down",
                        sentiment: ratio >= 1.3 ? :good : :neutral, weight: 72)
        end
        facts << fact("training:volume", "training",
                      t("insights.facts.volume", count:, distance: format.distance(distance, precision: 1)),
                      value: distance, unit: "m", weight: 55)
        facts
      end

      # --- the year before (comparisons) ------------------------------------

      def history_facts
        [
          usual_pace_fact, usual_heart_rate_fact, longest_since_fact, climb_since_fact,
          fastest_since_fact, similar_fact, gap_fact, year_total_fact
        ].compact
      end

      # The pace this workout held against the usual one over a comparable
      # distance, from four outings in the last ninety days.
      def usual_pace_fact
        rows = recent_rows(comparable_rows(workout[:distance].to_f), RECENT_DAYS)
                    .select { it[:average_speed].to_f.positive? }
        return if rows.size < 4

        if pace_display?
          current = current_pace
          return unless current

          usual = median(rows.filter_map { basis_pace(it[:average_speed]) })
          return unless usual

          delta = usual - current
          return if delta.abs < 2 || delta.abs.to_f / usual < 0.03

          key = delta.positive? ? "insights.facts.history_pace_faster" : "insights.facts.history_pace_slower"
          fact("history:pace", "history",
               t(key, delta: format.pace_delta(delta.abs, basis: pace_basis),
                       usual: format.pace(usual.round, basis: pace_basis)),
               value: delta, unit: "s/#{pace_basis} m", direction: delta.positive? ? "up" : "down",
               sentiment: delta.positive? ? :good : :neutral, weight: pace_weight(usual, delta))
        else
          current = workout[:average_speed].to_f
          return unless current.positive?

          usual = median(rows.map { it[:average_speed].to_f })
          return unless usual&.positive?

          delta = current - usual
          return if delta.abs.to_f / usual < 0.03

          key = delta.positive? ? "insights.facts.history_speed_faster" : "insights.facts.history_speed_slower"
          fact("history:pace", "history",
               t(key, delta: format.speed_delta(delta), usual: format.speed(usual)),
               value: delta, unit: "m/s", direction: delta.positive? ? "up" : "down",
               sentiment: delta.positive? ? :good : :neutral, weight: pace_weight(usual, delta))
        end
      end

      def pace_weight(usual, delta)
        return 48 unless delta.positive?

        delta.to_f / usual >= 0.06 ? 70 : 58
      end

      # The same pace for less heart: the trusty sign of a good day.
      def usual_heart_rate_fact
        current = workout[:average_heart_rate]
        current_pace = self.current_pace
        return unless current && current_pace

        rows = recent_rows(comparable_rows(workout[:distance].to_f), RECENT_DAYS)
               .select { it[:average_heart_rate] && it[:average_speed].to_f.positive? }
               .select { (basis_pace(it[:average_speed]).to_i - current_pace).abs <= current_pace * 0.03 }
        return if rows.size < 3

        usual = median(rows.map { it[:average_heart_rate].to_f })
        return unless usual

        delta = usual - current
        return if delta.abs < 4

        key = delta.positive? ? "insights.facts.history_heart_rate_lower" : "insights.facts.history_heart_rate_higher"
        fact("history:effort_hr", "history", t(key, delta: delta.abs.round), value: delta, unit: "bpm",
             direction: delta.positive? ? "up" : "down", sentiment: delta.positive? ? :good : :neutral,
             weight: delta.positive? ? 72 : 50)
      end

      def longest_since_fact
        distance = workout[:distance].to_f
        return if distance < MIN_DISTANCE || record_metric?("distance")
        return unless since_eligible?

        rows = history_rows.select { it[:distance].to_f >= distance }
        since_fact("history:longest_since", "insights.facts.longest_since", rows, weight: 76)
      end

      def climb_since_fact
        ascent = workout[:ascent].to_f
        return if ascent < MIN_ASCENT || record_metric?("ascent")
        return unless since_eligible?

        rows = history_rows.select { it[:ascent].to_f >= ascent }
        since_fact("history:climb_since", "insights.facts.climb_since", rows, weight: 74)
      end

      def fastest_since_fact
        return if workout[:distance].to_f < MIN_DISTANCE
        return if record_metric?("average_pace", "best_pace", "average_speed", "max_speed")
        return unless since_eligible?

        comparable = history_rows.select { it[:distance].to_f >= workout[:distance].to_f * COMPARABLE_LOW }
        return if comparable.size < FASTEST_MIN_COMPARABLE

        rows = comparable.select { faster_than_current?(it) }
        key = pace_display? ? "insights.facts.fastest_since" : "insights.facts.fastest_speed_since"
        since_fact("history:fastest_since", key, rows, weight: 76)
      end

      # A "since" comparison needs a habit to compare with: few outings in the
      # year, or a long break before this one, and only the gap says anything.
      def since_eligible? = history_rows.size >= SINCE_MIN_ROWS && !long_gap?

      def long_gap?
        last = last_same_sport_at
        last.nil? || started_at - last > LONG_GAP_DAYS * 86_400
      end

      def last_same_sport_at
        value = context.dig(:history, :last_same_sport_at)
        value && Time.iso8601(value)
      end

      # The last time this distance was matched or beaten, when it is at least
      # two months ago (or not in the year at all).
      def since_fact(id, key, rows, weight:)
        if rows.any?
          latest = rows.max_by { row_time(it) }
          return if row_time(latest) > started_at - (SINCE_DAYS * 86_400)

          display = t(key, date: row_date(latest))
        elsif context.dig(:history, :older_same_sport)
          display = t("#{key}_ever")
        else
          return
        end

        fact(id, "history", display, direction: "up", sentiment: :good, weight:)
      end

      def faster_than_current?(row)
        speed = row[:average_speed].to_f
        return false unless speed.positive?

        if pace_display?
          current = current_pace
          return false unless current

          basis_pace(speed).to_i < current
        else
          speed > workout[:average_speed].to_f
        end
      end

      # The closest comparable outing of the last ninety days, preferring the
      # one that shares the most places. The comparison is the pace, not the
      # moving time: ten percent of distance is minutes of clock.
      def similar_fact
        distance = workout[:distance].to_f
        ascent = workout[:ascent].to_f
        current = workout[:average_speed].to_f
        return unless distance.positive? && current.positive?

        rows = recent_rows(history_rows, RECENT_DAYS).select do |row|
          compare = row[:distance].to_f
          rise = row[:ascent].to_f
          next false unless compare.positive? && row[:average_speed].to_f.positive?
          next false unless (compare - distance).abs <= distance * SIMILAR_DISTANCE

          (rise - ascent).abs <= ascent * SIMILAR_ASCENT || (rise - ascent).abs <= SIMILAR_ASCENT_FLOOR
        end
        return if rows.empty?

        places = workout_places
        best = rows.max_by { |row| [ (Array(row[:places]) & places).size, row_time(row).to_i ] }
        other = best[:average_speed].to_f
        return if (current - other).abs / other < 0.02

        faster = current > other
        if pace_display?
          delta = (basis_pace(other) - basis_pace(current)).abs
          return if delta < 2

          key = faster ? "similar_pace_faster" : "similar_pace_slower"
          shown = format.pace_delta(delta, basis: pace_basis)
        else
          key = faster ? "similar_speed_faster" : "similar_speed_slower"
          shown = format.speed_delta(current - other)
        end
        fact("history:similar", "history",
             t("insights.facts.#{key}", date: row_date(best), distance: format.distance(best[:distance], precision: 1),
                                        ascent: format.elevation(best[:ascent]), delta: shown),
             value: current - other, unit: "m/s", direction: faster ? "up" : "down",
             sentiment: faster ? :good : :neutral, weight: 64)
      end

      def gap_fact
        last = last_same_sport_at
        return unless last

        days = ((started_at - last) / 86_400).floor
        return if days < GAP_DAYS

        display = days > 365 ? t("insights.facts.gap_year", sport: sport_name) : t("insights.facts.gap", count: days, sport: sport_name)
        fact("history:gap", "history", display, value: days, unit: "days", weight: 60)
      end

      # A round figure crossed in the member's own units: 100 km at a time to
      # 1 000, then every 500.
      def year_total_fact
        totals = context.dig(:history, :year_to_date)
        return unless totals.is_a?(Hash)

        distance = workout[:distance].to_f
        return unless distance.positive?

        before = distance_in_units(totals[:distance].to_f)
        after = distance_in_units(totals[:distance].to_f + distance)
        threshold = year_thresholds.select { it > before && it <= after }.max
        return unless threshold

        fact("history:year_total", "history",
             t("insights.facts.year_total", distance: format.distance(threshold_in_metres(threshold), precision: 0),
                                              sport: sport_name),
             value: threshold_in_metres(threshold), unit: "m", direction: "up", sentiment: :good, weight: 70)
      end

      def year_thresholds = (1..10).map { it * 100 } + (11..40).map { it * 500 }

      def distance_in_units(metres)
        imperial? ? Allure::Units.metres_to_miles(metres) : Allure::Units.metres_to_kilometres(metres)
      end

      def threshold_in_metres(value)
        imperial? ? value * Allure::Units::METRES_PER_MILE : value * Allure::Units::METRES_PER_KILOMETRE
      end

      # --- the places -------------------------------------------------------

      def place_facts
        names = workout_places
        return [] if names.empty?

        # A virtual world is the whole setting: one world fact, and nothing
        # about visits to a world that does not exist on a map.
        if sport[:virtual]
          return [ fact("place:venue", "place", t("insights.facts.venue", place: names.first), weight: 45) ]
        end

        facts = [ fact("place:route", "place", t("insights.facts.route", places: names.join(", ")), weight: 45) ]
        facts.concat(first_visit_facts(names))
        facts.concat(regular_place_facts(names))
        facts
      end

      # The id is the position, never the name: the model must copy it into
      # `fact_ids` verbatim, and an accent or an apostrophe is one chance to
      # fail too many.
      def first_visit_facts(names)
        return [] unless previous_workouts >= FIRST_VISIT_FLOOR

        index = names.each_index.find { |i| place_history[names[i]] && !place_history[names[i]][:seen_before] }
        return [] unless index

        [ fact("place:first:#{index}", "place", t("insights.facts.first_visit", place: names[index]),
               direction: "up", sentiment: :good, weight: 64) ]
      end

      def regular_place_facts(names)
        index, count = names.each_index.filter_map { |i| [ i, place_history.dig(names[i], :year_count).to_i ] }
                            .max_by { |_index, visits| visits }
        return [] unless index && count >= REGULAR_PLACE_FLOOR

        [ fact("place:regular:#{index}", "place",
               t("insights.facts.regular_place", count: count + 1, place: names[index]),
               value: count + 1, unit: "count", weight: 50) ]
      end

      def place_history = context.dig(:history, :places) || {}
      def previous_workouts = context.dig(:history, :previous_workouts).to_i
      # The serializer serves names, the context from a raw record may serve
      # `{name, kind}` entries: accept both.
      def workout_places
        Array(workout[:places]).filter_map do |place|
          case place
          when Hash then place["name"]
          when String then place
          end
        end
      end

      # --- the course -------------------------------------------------------

      # The route in sections, rendered for the model (AI.md §3.3): where each
      # one runs, what it is, how it went, and how it compares with the rest of
      # the outing. A section is never selected and never counted as a reason
      # to write more; it is the material a sentence is built from.
      def section_facts
        course = context[:course]
        return [] unless course.is_a?(Allure::Insights::Course)

        course.pairs.each_with_index.map { |(slot, section), index| section_fact(slot, section, index) }
      end

      def section_fact(slot, section, index)
        terrain = terrain_of(slot, section)
        parts = [ section_range(slot), section_terrain(slot, section, terrain), section_pace(section) ]
        parts << section_comparison(section) unless terrain == "descent"
        parts << t("insights.facts.section.heart_rate", bpm: section.heart_rate) if section.heart_rate
        parts << section_flat_equivalent(section) if terrain == "climb" && flat_equivalent?(section)
        fact("section:#{index + 1}", "section", parts.compact.join(" · "), weight: 0)
      end

      def section_range(slot)
        t("insights.facts.section.range", from: format.distance(slot.start_distance, precision: 1),
                                          to: format.distance(slot.end_distance, precision: 1))
      end

      def section_terrain(slot, section, terrain)
        case terrain
        when "climb"
          grade = format.grade(slot.grade || section.grade || 0.0)
          key = slot.name.present? ? "climb_named" : "climb"
          t("insights.facts.section.#{key}", name: slot.name,
                                             distance: format.distance(section.distance, precision: 1),
                                             grade:, ascent: format.elevation(section.ascent))
        when "descent"
          t("insights.facts.section.descent", descent: format.elevation(section.descent))
        else
          t("insights.facts.section.#{terrain}")
        end
      end

      def section_pace(section)
        if pace_display?
          pace = section.pace(pace_basis)
          pace && format.pace(pace, basis: pace_basis)
        else
          section.average_speed && format.speed(section.average_speed)
        end
      end

      # The pace against the workout's own average: a section is fast or slow
      # only relative to the rest of the same outing.
      def section_comparison(section)
        average = workout[:average_speed].to_f
        current = section.average_speed
        return unless average.positive? && current&.positive?

        relative = current / average - 1
        return if relative.abs < SECTION_AVERAGE_DELTA

        key = relative.positive? ? "vs_average_faster" : "vs_average_slower"
        t("insights.facts.section.#{key}", share: format.share(relative.abs))
      end

      # The flat-equivalent pace of a climb: the number that says « it was
      # slow because it went up », never a verdict on the effort.
      def flat_equivalent?(section)
        section.grade_adjusted_pace && section.grade_adjusted_coverage >= SECTION_ELEVATION_COVERAGE
      end

      def section_flat_equivalent(section)
        seconds = (section.grade_adjusted_pace * pace_basis / 1_000.0).round
        t("insights.facts.section.flat_equivalent", pace: format.pace(seconds, basis: pace_basis))
      end

      # Which terrain a section reads as: "between" is resolved once the
      # elevation is measured, and never claimed when it is missing.
      def terrain_of(slot, section)
        return slot.terrain unless slot.terrain == "between"
        return "rolling" unless section.elevation_coverage >= SECTION_ELEVATION_COVERAGE
        return "rolling" unless section.distance.to_f.positive?

        per_km = (section.ascent.to_f + section.descent.to_f) / (section.distance.to_f / 1_000)
        per_km < SECTION_FLAT_METRES_PER_KM ? "flat" : "rolling"
      end

      # --- what the sections say (AI.md §3.3) -------------------------------

      # The story of the course, on comparable ground: flat against flat, a
      # climb at its flat-equivalent pace. None of these compares one section
      # of one terrain with a section of another.
      def course_facts
        course = context[:course]
        return [] unless course.is_a?(Allure::Insights::Course)

        [
          finish_fact(course), fade_fact(course), climb_held_fact(course), heart_rate_course_fact(course),
          climb_share_fact(course)
        ].compact
      end

      # Both ends of the route on ground that compares: the first and the last
      # level sections. A climb is never a finish, whatever its gradient.
      def finish_fact(course)
        first, last = level_ends(course)
        return unless first && last

        first_speed = first.average_speed
        last_speed = last.average_speed
        return unless first_speed&.positive? && last_speed&.positive?
        return unless last_speed / first_speed - 1 >= COURSE_FINISH_DELTA

        fact("course:finish", "course",
             t("insights.facts.course.strong_finish", last: rendered_pace(last), first: rendered_pace(first)),
             value: last_speed - first_speed, unit: "m/s", direction: "up", sentiment: :good, weight: 70)
      end

      def fade_fact(course)
        first, last = level_ends(course)
        return unless first && last

        first_speed = first.average_speed
        last_speed = last.average_speed
        return unless first_speed&.positive? && last_speed&.positive?
        return unless last_speed / first_speed - 1 <= -COURSE_FADE_DELTA
        # A higher heart rate late on is a harder finish, not a fade.
        return if first.heart_rate && last.heart_rate && last.heart_rate < first.heart_rate

        fact("course:fade", "course",
             t("insights.facts.course.fade", last: rendered_pace(last), first: rendered_pace(first)),
             value: last_speed - first_speed, unit: "m/s", direction: "down", sentiment: :neutral, weight: 62)
      end

      # The first and the last section on level ground, nil when the route
      # offers fewer than two.
      def level_ends(course)
        pairs = course.pairs.select { |slot, section| level_ground?(slot, section) }
        return if pairs.length < 2

        [ pairs.first[1], pairs.last[1] ]
      end

      # The climb held at the pace of the flat: the clearest sign of an even
      # effort on a route that climbs.
      def climb_held_fact(course)
        return unless pace_display?

        climb = course.pairs.select { |slot, _section| slot.terrain == "climb" }
                        .max_by { |_slot, section| section.ascent.to_f }
        return unless climb

        slot, section = climb
        gap = section.grade_adjusted_pace
        return unless gap&.positive? && section.grade_adjusted_coverage >= SECTION_ELEVATION_COVERAGE

        flats = course.pairs.select { |other, measured| level_ground?(other, measured) }
                         .filter_map { |_other, measured| measured.average_speed }
        return if flats.length < 2

        flat_speed = flats.sum / flats.length
        return unless flat_speed.positive?

        # The grade-adjusted pace reads in seconds per kilometre, the flat
        # sections in speed: compare the flat-equivalent speed.
        equivalent = 1_000.0 / gap
        return if (equivalent / flat_speed - 1).abs > COURSE_CLIMB_HELD

        fact("course:climb_held", "course",
             t("insights.facts.course.climb_held",
               name: slot.name.presence || t("insights.facts.section.climb_fallback"),
               gap: format.pace((gap * pace_basis / 1_000.0).round, basis: pace_basis),
               flat: format.pace((pace_basis / flat_speed).round, basis: pace_basis)),
             value: equivalent, unit: "m/s", direction: "up", sentiment: :good, weight: 72)
      end

      # The same pace on the flat, for more heart: the drift a series cannot
      # tell apart from the terrain, read here on comparable ground.
      def heart_rate_course_fact(course)
        pairs = course.pairs.select { |slot, section| level_ground?(slot, section) }
        return if pairs.length < 2

        first = pairs.first[1]
        last = pairs.last[1]
        return unless first.heart_rate && last.heart_rate
        return unless first.average_speed&.positive? && last.average_speed&.positive?
        return if (last.average_speed / first.average_speed - 1).abs > COURSE_PACE_MATCH

        delta = last.heart_rate - first.heart_rate
        return if delta.to_f / first.heart_rate < COURSE_HEART_RATE_DELTA

        fact("course:hr_flat", "course", t("insights.facts.course.hr_flat", delta:),
             value: delta, unit: "bpm", direction: "up", sentiment: :neutral, weight: 64)
      end

      def climb_share_fact(course)
        climbs = course.pairs.select { |slot, _section| slot.terrain == "climb" }
        return if climbs.length < 2

        moving = course.sections.sum { it.moving_time.to_f }
        return unless moving.positive?

        climbing = climbs.sum { |_slot, section| section.moving_time.to_f }
        share = climbing / moving
        return if share < COURSE_CLIMB_SHARE

        fact("course:climb_share", "course", t("insights.facts.course.climb_share", share: format.share(share)),
             value: share, unit: "share", weight: 58)
      end

      def level_ground?(slot, section) = %w[flat part].include?(terrain_of(slot, section))

      def rendered_pace(section) = section_pace(section)

      # --- pace over the splits --------------------------------------------

      def pacing_facts
        rows = Array(context.dig(:splits, :rows)).reject { it[:partial] }.select { it[:distance].to_f.positive? }
        return [] if rows.length < 3

        best = rows.min_by { |row| row[:elapsed_time].to_f / row[:distance].to_f }
        return [] unless best

        [ fact("pacing:best_split", "pacing",
               t("insights.facts.best_split", distance: format.distance(best[:distance], precision: 1),
                                              time: format.duration(best[:elapsed_time])),
               value: best[:elapsed_time], unit: "s", weight: 56) ]
      end

      # --- heart rate -------------------------------------------------------

      def heart_rate_facts
        facts = []
        average = workout[:average_heart_rate]
        if average
          maximum = workout[:max_heart_rate]
          display = maximum ? t("insights.facts.heart_rate", average:, max: maximum) : format.bpm(average)
          facts << fact("heart_rate:average", "heart_rate", display, value: average, unit: "bpm", weight: 60)
        end
        zones = workout.dig(:heart_rate, :zones)
        if zones.is_a?(Array) && zones.sum.positive?
          index = zones.each_with_index.max_by { it[0] }[1]
          share = zones[index].to_f / zones.sum
          facts << fact("heart_rate:zone", "heart_rate",
                        t("insights.facts.zone", share: format.share(share), zone: index + 1),
                        value: share, unit: "share", weight: 62)
        end
        facts
      end

      # --- weather ----------------------------------------------------------

      def weather_facts
        weather = workout[:weather]
        summary = weather && weather[:summary]
        return [] unless weather && weather[:status] == "ready" && summary.is_a?(Hash)

        facts = []
        exposure = summary[:wind_exposure]
        if exposure.is_a?(Hash)
          head = exposure[:head].to_f
          tail = exposure[:tail].to_f
          if head >= 0.1 || tail >= 0.1
            facts << fact("weather:wind", "weather",
                          t("insights.facts.wind", head: format.share(head), tail: format.share(tail)),
                          value: head, unit: "share", sentiment: head >= 0.25 ? :bad : :neutral,
                          weight: head >= 0.25 ? 78 : 52)
          end
        end
        low = summary[:temperature_min]
        high = summary[:temperature_max]
        if low && high
          facts << fact("weather:temperature", "weather",
                        t("insights.facts.temperature", range: format.temperature_range(low, high),
                                                        condition: condition(summary[:condition]),
                                                        apparent: format.temperature(summary[:apparent_temperature])),
                        value: high, unit: "°C", weight: 50)
        end
        facts
      end

      def condition(token) = t("weather.conditions.#{token}", default: token.to_s)

      # --- detected sections -----------------------------------------------

      def climb_facts
        climb = Array(context.dig(:laps, :detected, "climb")).max_by { it[:ascent].to_f }
        return [] unless climb && climb[:ascent].to_f.positive?

        name = climb[:name].presence || t("workouts.show.laps.sources.climb")
        [ fact("climb:#{climb[:number]}", "climb",
               t("insights.facts.climb", name:, distance: format.distance(climb[:distance], precision: 1),
                                         grade: format.grade(climb[:average_grade])),
               value: climb[:ascent], unit: "m", weight: 55) ]
      end

      def interval_facts
        rows = Array(context.dig(:laps, :detected, "speed_interval"))
        return [] if rows.length < 3

        longest = rows.max_by { it[:distance].to_f }
        [ fact("interval:speed", "interval",
               t("insights.facts.intervals", count: rows.length,
                                             distance: format.distance(longest[:distance], precision: 1),
                                             speed: format.speed(longest[:average_speed])),
               value: rows.length, unit: "count", weight: 40) ]
      end

      # --- selection and helpers -------------------------------------------

      def history_rows = Array(context.dig(:history, :same_sport))

      def row_time(row) = Time.iso8601(row.fetch(:started_at))

      # The member's local date of a history row, as the UI would print it.
      def row_date(row) = format.date(Time.iso8601(row.fetch(:local_start)))

      def started_at = @started_at ||= Time.iso8601(workout.fetch(:started_at))

      def recent_rows(rows, days) = rows.select { row_time(it) >= started_at - (days * 86_400) }

      def comparable_rows(distance)
        return [] unless distance.to_f.positive?

        history_rows.select do |row|
          item = row[:distance].to_f
          item.positive? && item >= distance * COMPARABLE_LOW && item <= distance * COMPARABLE_HIGH
        end
      end

      def current_pace
        pace = workout[:average_pace] || basis_pace(workout[:average_speed])
        pace&.to_i&.positive? ? pace.to_i : nil
      end

      # Seconds per pace basis, from a speed.
      def basis_pace(speed)
        speed = speed.to_f
        return unless speed.positive?

        (pace_basis / speed).round
      end

      def median(values)
        values = values.compact.sort
        return if values.empty?

        middle = values.size / 2
        values.size.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2.0
      end

      def record_metric?(*metrics)
        Array(context.dig(:records_set, :records)).any? { metrics.include?(it[:metric].to_s) }
      end

      def imperial? = context.dig(:account, :unit_system).to_s == "imperial"

      def selected(facts)
        baseline = facts.select { it.kind == "baseline" }
        rest = facts.reject { it.kind == "baseline" || it.kind == "section" }
                    .sort_by { |item| [ -item.weight, KINDS.index(item.kind), item.id ] }
        chosen = []
        per_kind = Hash.new(0)
        rest.each do |item|
          break if baseline.length + chosen.length >= MAX_FACTS
          next if per_kind[item.kind] >= per_kind_limit(item.kind)

          chosen << item
          per_kind[item.kind] += 1
        end
        (baseline + chosen).first(MAX_FACTS)
      end

      def per_kind_limit(kind) = kind == "history" ? HISTORY_PER_KIND : PER_KIND

      def place_word(place) = %w[first second third][place.to_i - 1]
    end
  end
end
