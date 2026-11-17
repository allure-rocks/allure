# frozen_string_literal: true

module Segments
  # The segment index's list query (docs/dev/SEGMENTS.md, DESIGN.md §20.6):
  # the sport filter and the canonical sort key, parsed once from request
  # params, applied to the viewer's visible courses of one kind.
  #
  # The list has one row per course and sport: a course with a sport is one
  # row; an all-sports course is one row per sport it was run in — on the
  # board the viewer reads, or by the viewer — each with that sport's record
  # and the viewer's best, and a single « Tous les sports » row while nobody
  # ran it. Each row carries `row_sport_id`. A sport filter keeps the rows of
  # the chosen sports and the all-sports courses nobody ran yet. Missing
  # values (no ascent, no record, no effort of the viewer's) sort last in both
  # directions.
  class ListQuery
    SORTS = %w[created name distance ascent grade record best].freeze
    DIRECTIONS = %w[asc desc].freeze
    SORT_KEYS = SORTS.flat_map { |field| [ "#{field}_desc", "#{field}_asc" ] }.freeze
    DEFAULT_SORT = "created_desc"
    ROW_SPORT = "COALESCE(segments.sport_id, row_sports.sport_id)"

    # The course glyph's simplification tolerance, as a fraction of the
    # course's larger bounding-box side: about one pixel of the drawn glyph.
    THUMBNAIL_TOLERANCE = 1.0 / 60

    def initialize(viewer:, params:, kind: "segment")
      @viewer = viewer
      @params = params
      @kind = kind
    end

    def resolve(scope)
      scope = expand_sports(scope)
      scope = apply_sport(scope)
      scope = apply_sort(scope)
      scope.select(
        "segments.*",
        Arel.sql("#{ROW_SPORT} AS row_sport_id"),
        Arel.sql(
          "ST_AsGeoJSON(ST_SimplifyPreserveTopology(segments.geom::geometry, " \
          "GREATEST(segments.bounds[3] - segments.bounds[1], segments.bounds[4] - segments.bounds[2]) " \
          "* #{THUMBNAIL_TOLERANCE}), 5) AS thumbnail_geojson"
        )
      )
    end

    # The sports of the unfiltered rows, most frequent first; the all-sports
    # rows nobody ran are counted under none of them.
    def practiced_sports(scope)
      counts = expand_sports(scope).unscope(:order, :select).where(Arel.sql("#{ROW_SPORT} IS NOT NULL"))
        .group(Arel.sql(ROW_SPORT)).count
      Sport.where(id: counts.keys).to_a
        .sort_by { |sport| [ -counts.fetch(sport.id), sport.position ] }
        .map { |sport| { sport:, count: counts.fetch(sport.id) } }
    end

    def sport_ids
      Array(@params[:sports]).map(&:to_s).select { |id| id.match?(/\A\d+\z/) }.uniq
    end

    # Routes and loops are never shared, so they have no board and no record
    # to sort by.
    def records? = @kind == "segment"

    def sort_keys
      records? ? SORT_KEYS : SORT_KEYS.reject { it.start_with?("record_") }
    end

    def sort_key
      key = @params[:sort].to_s
      sort_keys.include?(key) ? key : DEFAULT_SORT
    end

    def sort = sort_key.rpartition("_").first
    def direction = sort_key.rpartition("_").last

    private

    # The sports an all-sports course was run in: the efforts on the board the
    # viewer reads, plus the viewer's own.
    def expand_sports(scope)
      visible = Listing.all_eligible(viewer: @viewer).unscope(:order)
        .select("segment_efforts.segment_id", "segment_efforts.sport_id")
      own = SegmentEffort.where(user_id: @viewer.id).select(:segment_id, :sport_id)
      scope.joins(
        "LEFT JOIN (SELECT DISTINCT segment_id, sport_id FROM ((#{visible.to_sql}) UNION (#{own.to_sql})) " \
        "AS run_sports) AS row_sports ON segments.sport_id IS NULL AND row_sports.segment_id = segments.id"
      )
    end

    def apply_sport(scope)
      ids = sport_ids
      return scope if ids.empty?

      scope.where("#{ROW_SPORT} IN (?) OR #{ROW_SPORT} IS NULL", ids.map(&:to_i))
    end

    def apply_sort(scope)
      dir = direction == "asc" ? "ASC" : "DESC"
      tie_break = [ Arel.sql("segments.id DESC"), Arel.sql("#{ROW_SPORT} ASC NULLS FIRST") ]
      case sort
      when "record"
        scope
          .joins("LEFT JOIN (#{record_times.to_sql}) AS segment_records ON segment_records.segment_id = segments.id " \
                 "AND segment_records.sport_id = #{ROW_SPORT}")
          .order(Arel.sql("segment_records.record_time #{dir} NULLS LAST"), *tie_break)
      when "best"
        scope
          .joins("LEFT JOIN (#{viewer_best_times.to_sql}) AS viewer_bests ON viewer_bests.segment_id = segments.id " \
                 "AND viewer_bests.sport_id = #{ROW_SPORT}")
          .order(Arel.sql("viewer_bests.best_time #{dir} NULLS LAST"), *tie_break)
      when "name"
        scope.order(Arel.sql("LOWER(segments.name) #{dir}"), *tie_break)
      else
        # The elevation column shows the leading figure (ascent or descent) and
        # the grade sorts by steepness, a descent as steep as a climb.
        expression = {
          "created" => "segments.created_at",
          "distance" => "segments.distance",
          "ascent" => "GREATEST(segments.ascent, segments.descent)",
          "grade" => "ABS(segments.average_grade)"
        }.fetch(sort)
        scope.order(Arel.sql("#{expression} #{dir} NULLS LAST"), *tie_break)
      end
    end

    # The best time per course and sport on the board the viewer reads.
    def record_times
      Listing.all_eligible(viewer: @viewer)
        .unscope(:order)
        .group("segment_efforts.segment_id", "segment_efforts.sport_id")
        .select("segment_efforts.segment_id AS segment_id", "segment_efforts.sport_id AS sport_id",
                "MIN(segment_efforts.elapsed_time) AS record_time")
    end

    def viewer_best_times
      SegmentEffort
        .where(user_id: @viewer.id)
        .group(:segment_id, :sport_id)
        .select("segment_efforts.segment_id AS segment_id", "segment_efforts.sport_id AS sport_id",
                "MIN(segment_efforts.elapsed_time) AS best_time")
    end
  end
end
