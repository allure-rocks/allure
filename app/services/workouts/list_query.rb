# frozen_string_literal: true

module Workouts
  # The owner's workout-list query (DESIGN.md §13): the sport, period,
  # publication, commute, place and free-text filters, plus the canonical sort
  # key, parsed once from request params. Shared by WorkoutsController and the
  # bulk selection, so a bulk operation can replay exactly the list the owner
  # is looking at (PLAN_BULK_ACTIONS.md §2).
  class ListQuery
    PERIODS = [ "all", *Allure::Stats::Periods::KEYS, "custom" ].freeze
    PUBLICATIONS = %w[all published not_published].freeze
    COMMUTES = %w[all commute non_commute].freeze

    SORTS = {
      "date" => "started_at",
      "distance" => "distance",
      "duration" => "duration",
      "ascent" => "ascent"
    }.freeze
    DIRECTIONS = %w[asc desc].freeze

    # One sort select encodes field and direction in a single URL parameter
    # (§10.6, §10.5); the table headers write the same values. A legacy
    # `sort=distance&direction=asc` pair still resolves.
    SORT_KEYS = SORTS.keys
      .flat_map { |field| [ "#{field}_desc", "#{field}_asc" ] }.freeze

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    # The filtered and sorted relation. Pagination, `includes` and the view
    # mode stay with the caller.
    def resolve(scope: @user.workouts)
      scope = apply_sport(scope)
      scope = apply_period(scope)
      scope = apply_publication(scope)
      scope = apply_commute(scope)
      scope = apply_place(scope)
      scope = apply_search(scope)
      apply_sort(scope)
    end

    # Workout list filters (§13): every filter is a URL parameter, so back /
    # forward work and a filtered view is shareable. Filtering never resets the
    # sort; pagination preserves the params through url_for.
    def sport_ids
      Array(@params[:sports]).map(&:to_s).select { |id| id.match?(/\A\d+\z/) }.uniq
    end

    def period = PERIODS.include?(@params[:period]) ? @params[:period] : "all"

    def publication = PUBLICATIONS.include?(@params[:publication]) ? @params[:publication] : "all"
    def commute = COMMUTES.include?(@params[:commute]) ? @params[:commute] : "all"
    def query = @params[:q].to_s.strip
    def place = @params[:place].to_s.strip.truncate(120)

    # Field and direction as one canonical key; a legacy `sort` + `direction`
    # pair (or a bare `sort`) resolves to the same value, so old links and the
    # table headers share one URL shape.
    def sort_key
      key = @params[:sort].to_s
      return key if SORT_KEYS.include?(key)

      direction = DIRECTIONS.include?(@params[:direction]) ? @params[:direction] : "desc"
      legacy = "#{key}_#{direction}"
      SORT_KEYS.include?(legacy) ? legacy : "date_desc"
    end

    def sort = sort_key.split("_", 2).first
    def direction = sort_key.split("_", 2).last

    private

    def apply_sport(scope)
      ids = sport_ids
      ids.any? ? scope.where(sport_id: ids) : scope
    end

    # Periods are viewer-calendar windows, never rolling SQL offsets (§8.4):
    # the bounds are built in the viewer's zone so a "Cette semaine" filter
    # matches the hub's week exactly.
    def apply_period(scope)
      if period == "custom"
        from = parse_date(@params[:from])
        to = parse_date(@params[:to])
        zone = viewer_time_zone
        scope = scope.where("started_at >= ?", zone.local(from.year, from.month, from.day)) if from
        scope = scope.where("started_at <= ?", zone.local(to.year, to.month, to.day).end_of_day) if to
        return scope
      end

      range = Allure::Stats::Periods.range(period, today: viewer_today, week_start: @user.week_start)
      return scope unless range

      zone = viewer_time_zone
      bounds = zone.local(range.begin.year, range.begin.month, range.begin.day)..
        zone.local(range.end.year, range.end.month, range.end.day).end_of_day
      scope.where(started_at: bounds)
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # A workout counts as published while any audience's publication is active
    # (PLAN_AUDIENCES.md §2).
    def apply_publication(scope)
      published = WorkoutPublication.active.select(:workout_id)
      case publication
      when "published" then scope.where(id: published)
      when "not_published" then scope.where.not(id: published)
      else scope
      end
    end

    def apply_commute(scope)
      case commute
      when "commute" then scope.where(commute: true)
      when "non_commute" then scope.where(commute: false)
      else scope
      end
    end

    def apply_place(scope)
      return scope if place.blank?

      pattern = "%#{place.gsub(/[%_\\]/) { |match| "\\#{match}" }}%"
      scope.where(
        "EXISTS (SELECT 1 FROM workout_place_names AS recorded_place " \
          "WHERE recorded_place.workout_id = workouts.id AND recorded_place.name ILIKE ? ESCAPE '\\')",
        pattern
      )
    end

    def apply_search(scope)
      return scope if query.blank?

      pattern = "%#{query.gsub(/[%_\\]/) { |match| "\\#{match}" }}%"
      scope.where("workouts.title ILIKE ? ESCAPE '\\' OR workouts.description ILIKE ? ESCAPE '\\'", pattern, pattern)
    end

    def apply_sort(scope)
      scope.order(SORTS.fetch(sort) => direction, id: :desc)
    end

    def viewer_time_zone = Time.find_zone(@user&.time_zone) || Time.zone
    def viewer_today = viewer_time_zone.today
  end
end
