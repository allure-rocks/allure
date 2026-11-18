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
      MAX_FACTS = 16
      PER_KIND = 3
      KINDS = %w[baseline record segment comparison training pacing heart_rate weather climb interval].freeze
      # The context section each kind reads, unless a detector overrides it.
      SOURCES = {
        "baseline" => "workout", "record" => "records_set", "segment" => "segment_efforts",
        "comparison" => "segment_efforts", "training" => "training", "pacing" => "splits",
        "heart_rate" => "workout", "weather" => "workout", "climb" => "laps", "interval" => "laps"
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
      end

      def initialize(context, locale:)
        @context = context
        @locale = locale.to_sym
        @format = Format.new(locale: @locale, unit_system: context.dig(:account, :unit_system) || "metric")
      end

      def build
        selected(
          baseline_facts + record_facts + segment_facts + comparison_facts + training_facts +
          pacing_facts + heart_rate_facts + weather_facts + climb_facts + interval_facts
        )
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
        formatted = format_record(record)
        return unless formatted

        label = t("records.types.#{record[:type].to_s.downcase}", default: record[:type].to_s)
        fact("record:#{record[:sport]}:#{record[:type]}", "record", "#{label} : #{formatted}",
             value: record[:value], unit: record[:metric], direction: "up", sentiment: :good, weight: 92)
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

        label = t("records.distances.#{effort[:distance_key]}", default: effort[:distance_key].to_s)
        display = t("insights.facts.effort", place: t("insights.facts.places.#{place_word(place)}"), label:,
                                            time: format.duration(effort[:elapsed_time]))
        fact("record:best_effort:#{effort[:distance_key]}", "record", display, value: effort[:elapsed_time], unit: "s",
             direction: "up", sentiment: :good, weight: place == 1 ? 95 : 82, source: "best_efforts")
      end

      # --- segments and their comparison ------------------------------------

      def segment_facts
        Array(context[:segment_efforts]).filter_map do |effort|
          name = effort.dig(:segment, :name)
          next if name.blank?

          rank = effort.dig(:leaderboard, :rank)
          place = effort[:personal_place]
          participants = effort.dig(:leaderboard, :participants).to_i
          if rank && rank <= 3 && participants >= 3
            display = t("insights.facts.rank", place: t("insights.facts.ranks.#{place_word(rank)}"), label: name,
                                              count: participants)
            fact("segment:rank:#{effort.dig(:segment, :id)}", "segment", display, value: rank, unit: "rank",
                 direction: "up", sentiment: :good, weight: 88)
          elsif place && place <= 3
            display = t("insights.facts.effort", place: t("insights.facts.places.#{place_word(place)}"), label: name,
                                                time: format.duration(effort[:elapsed_time]))
            fact("segment:best:#{effort.dig(:segment, :id)}", "segment", display, value: effort[:elapsed_time],
                 unit: "s", direction: "up", sentiment: :good, weight: place == 1 ? 90 : 80)
          end
        end
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

      # --- pace over the splits --------------------------------------------

      def pacing_facts
        rows = Array(context.dig(:splits, :rows)).reject { it[:partial] }.select { it[:distance].to_f.positive? }
        return [] if rows.length < 3

        facts = []
        middle = rows.length / 2
        first_pace = average_pace(rows[0...middle])
        second_pace = average_pace(rows[middle..])
        if first_pace && second_pace
          delta = ((second_pace - first_pace) * 1_000).round
          if delta.abs >= 3
            key = delta.negative? ? "insights.facts.negative_split" : "insights.facts.positive_split"
            facts << fact("pacing:halves", "pacing", t(key, delta: format.duration_span(delta.abs)),
                          value: delta, unit: "s/km", direction: delta.negative? ? "up" : "down",
                          sentiment: delta.negative? ? :good : :neutral, weight: 66)
          end
        end
        best = rows.min_by { |row| row[:elapsed_time].to_f / row[:distance].to_f }
        if best
          facts << fact("pacing:best_split", "pacing",
                        t("insights.facts.best_split", distance: format.distance(best[:distance], precision: 1),
                                                       time: format.duration(best[:elapsed_time])),
                        value: best[:elapsed_time], unit: "s", weight: 56)
        end
        facts
      end

      def average_pace(rows)
        distance = rows.sum { it[:distance].to_f }
        distance.positive? ? rows.sum { it[:elapsed_time].to_f } / distance : nil
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
        drift = heart_rate_drift
        facts << drift if drift
        facts
      end

      def heart_rate_drift
        rows = Array(context[:series]).select { it[:heart_rate] }
        return if rows.length < 60

        middle = rows.length / 2
        first = rows[0...middle].sum { it[:heart_rate] }.to_f / middle
        second = rows[middle..].sum { it[:heart_rate] }.to_f / (rows.length - middle)
        return if first <= 0

        drift = (second - first) / first * 100
        return if drift.abs < 3

        fact("heart_rate:drift", "heart_rate", t("insights.facts.drift", percent: format.share(drift.abs / 100)),
             value: drift, unit: "%", direction: "up", weight: 68)
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

      def selected(facts)
        baseline = facts.select { it.kind == "baseline" }
        rest = facts.reject { it.kind == "baseline" }
                    .sort_by { |item| [ -item.weight, KINDS.index(item.kind), item.id ] }
        chosen = []
        per_kind = Hash.new(0)
        rest.each do |item|
          break if baseline.length + chosen.length >= MAX_FACTS
          next if per_kind[item.kind] >= PER_KIND

          chosen << item
          per_kind[item.kind] += 1
        end
        (baseline + chosen).first(MAX_FACTS)
      end

      def place_word(place) = %w[first second third][place.to_i - 1]
    end
  end
end
