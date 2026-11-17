# frozen_string_literal: true

module Segments
  # Recognize known owner loops independently of bounded new-loop discovery,
  # without persisting speculative courses. A spatial closure alone proves
  # neither a complete traversal nor its direction.
  class LoopDetection
    Result = Data.define(:candidate, :segment, :matches)

    def initialize(workout:, points:)
      @workout = workout
      @points = points
    end

    def call
      matched_segments = {}
      results = CandidateQuery.for_loop_workout(@workout).order(:id).filter_map do |segment|
        matches = matched_segments[segment.id] = summaries(segment)
        next if matches.empty?

        Result.new(candidate: nil, segment:, matches:)
      end
      results.concat(candidates.filter_map do |candidate|
        reused = LoopReuse.new(workout: @workout, candidate:).call
        next if reused && results.any? { |result| result.segment&.id == reused.id }

        matches = if reused
          matched_segments[reused.id] ||= summaries(reused)
        else
          summaries(preview(candidate))
        end
        minimum = reused ? 1 : MatchWorkoutJob::MIN_LOOP_OCCURRENCES
        next if matches.length < minimum

        Result.new(candidate:, segment: reused, matches:)
      end)
      return if results.empty?

      # Equivalent coverage (within 1%) favours elementary tours, not a course
      # comprising two tours. Then prefer coverage and the earliest source cut.
      # A loop the owner renamed is the identity they chose: it wins the
      # equivalent-coverage comparison whatever its age, so a reconciliation
      # never takes a renamed loop's efforts away (docs/dev/SEGMENTS.md).
      coverage = ->(result) { result.matches.sum(&:distance) }
      maximum = results.map(&coverage).max
      results.select { |result| coverage.call(result) >= maximum * 0.99 }
        .max_by { |result| [ result.segment&.renamed? ? 1 : 0, result.matches.length, coverage.call(result), -result.matches.first.start_point_index, -(result.segment&.id || Float::INFINITY) ] }
    end

    private

    def summaries(segment)
      Allure::Segments::Matcher.new(segment:, points: @points).call(summary_only: true)
    end

    def candidates
      # Never close a circuit across a recording gap. Translate local indexes
      # back to the global stream consumed by Creator and the chart.
      discovered = @points.chunk(&:segment_index).flat_map do |_segment_index, points|
        next [] if points.length < 2 || points.any? { |point| point.longitude.nil? || point.latitude.nil? }

        Allure::Geometry::LoopCandidates.new(points.map(&:coordinate)).ranked.map do |result|
          candidate = result.candidate.with(
            start_index: points.first.index + result.candidate.start_index,
            end_index: points.first.index + result.candidate.end_index
          )
          [ candidate, result.occurrences ]
        end
      end
      discovered.sort_by { |candidate, count| [ -(count >= 2 ? 1 : 0), -candidate.travelled_distance_meters * count, candidate.start_index ] }
        .first(Allure::Geometry::LoopCandidates::MAX_CANDIDATES).map(&:first)
    end

    def preview(candidate)
      factory = RGeo::Geographic.spherical_factory(srid: 4326)
      Segment.new(
        kind: "loop", distance: candidate.travelled_distance_meters,
        match_tolerance_meters: Creator::DEFAULT_MATCH_TOLERANCE_METERS,
        signature: Allure::Geometry::ShapeSignature.compute(candidate.coordinates),
        geom: factory.line_string(candidate.coordinates.map { |coordinate| factory.point(*coordinate) })
      )
    end
  end
end
