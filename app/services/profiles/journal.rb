# frozen_string_literal: true

module Profiles
  # A profile's journal reads only its already-authorized publications. Local
  # callers pass the narrowest publication per workout; remote callers pass
  # the viewer's entitled notes. Counts, filters and ordering never consult a
  # source workout, and grouping in SQL keeps unpaginated snapshots out of memory.
  class Journal
    PERIODS = [ "all", *Allure::Stats::Periods::KEYS ].freeze
    SportEntry = Data.define(:key, :value, :sport, :count)

    attr_reader :period, :selected_sport

    def initialize(scope:, viewer:, sport: nil, period: nil)
      @scope = scope
      @viewer = viewer
      @remote = scope.klass == RemoteNote
      @period = PERIODS.include?(period) ? period : "all"
      if sport.is_a?(String)
        key = @remote ? "label:#{sport.delete_prefix('label:').strip.downcase}" : sport
        @selected_sport = sports.find { |entry| entry.key == key }
      end
    end

    def sports
      @sports ||= sport_rows.map do |value, label, count|
        sport = if @remote
          catalog.find_label(label) || Federation::RemoteNoteView::SportFallback.new(
            label: label.presence || I18n.t("remote_notes.unknown_sport")
          )
        else
          catalog.fetch_slug!(value)
        end
        SportEntry.new(key: @remote ? "label:#{value}" : value, value:, sport:, count:)
      end.sort_by { |entry| [ -entry.count, entry.key ] }
    end

    def total_count = sports.sum(&:count)
    def filtered? = selected_sport.present? || period != "all"

    def selector_sports
      sports.filter_map do |entry|
        count = period_counts.fetch(entry.value, 0)
        entry.with(count:) if count.positive? || entry == selected_sport
      end.sort_by { |entry| [ -entry.count, entry.key ] }
    end

    def mix? = selected_sport.nil? && selector_sports.many?

    def relation
      scope = period_scope
      scope = scope.where(sport_expression.eq(selected_sport.value)) if selected_sport
      scope.order(started_at_expression.desc.nulls_last, id: :desc)
    end

    def items_for(rows)
      rows.map do |record|
        Federation::FollowingFeed::Item.new(
          kind: @remote ? "remote" : "local",
          record: @remote ? record : record.workout,
          published_at: record.published_at || (@remote ? record.received_at : nil),
          publication: @remote ? nil : record
        )
      end
    end

    private

    def catalog = @catalog ||= Sport.catalog

    def sport_expression
      if @remote
        Arel.sql("COALESCE(LOWER(BTRIM(remote_notes.sport_label)), '')")
      else
        Arel.sql("workout_publications.representation ->> 'sport_slug'")
      end
    end

    def started_at_expression
      @remote ? RemoteNote.arel_table[:started_at] : Arel.sql("(workout_publications.representation ->> 'started_at')::timestamptz")
    end

    def grouped_counts(scope) = scope.group(sport_expression).count

    # Remote labels match the catalog case-insensitively, like RemoteNoteView.
    # Keep one original spelling for an unknown label, without hydrating notes.
    def sport_rows
      if @remote
        @scope.group(sport_expression).pluck(sport_expression, Arel.sql("MIN(remote_notes.sport_label)"), Arel.sql("COUNT(*)"))
      else
        grouped_counts(@scope).map { |value, count| [ value, value, count ] }
      end
    end

    def period_counts
      @period_counts ||= period == "all" ? sports.to_h { |entry| [ entry.value, entry.count ] } : grouped_counts(period_scope)
    end

    def period_scope
      @period_scope ||= begin
        zone = Time.find_zone!(@viewer.time_zone)
        range = Allure::Stats::Periods.range(period, today: zone.today, week_start: @viewer.week_start)
        if range
          @scope.where(started_at_expression.gteq(range.begin.in_time_zone(zone))
            .and(started_at_expression.lt((range.end + 1).in_time_zone(zone))))
        else
          @scope
        end
      end
    end
  end
end
