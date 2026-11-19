# frozen_string_literal: true

module Workouts
  # The facts of one workout and their digest (docs/dev/AI.md §3.1): the
  # owner-only context, the route cut into sections, and the member's language
  # and units. Pure apart from reading the track.
  class SummaryFacts
    # The terrain claim trusts the stored point profile only while each section
    # carries nearly all its elevation and the total matches the workout's own
    # ascent: a FIT file may hold device totals over a poor altitude channel.
    SECTION_COVERAGE = 0.9
    ASCENT_TOLERANCE = 0.5
    ASCENT_FLOOR = 40.0

    Snapshot = Data.define(:facts, :digest, :locale, :unit_system, :course)

    def initialize(workout)
      @workout = workout
    end

    def call
      locale = workout.user.locale
      unit_system = workout.user.unit_system
      context = ContextPayload.new(workout, user: workout.user).call(include_history: true)
      course = course(context)
      context[:course] = course if course
      facts = Allure::Insights::Facts.build(context, locale:)
      digest = Allure::Insights::Facts.digest(facts, version: Allure::Insights::VERSION,
                                              locale:, unit_system:)
      Snapshot.new(facts:, digest:, locale:, unit_system:, course:)
    end

    private

    attr_reader :workout

    # The route in sections (AI.md §3.3): first the terrain the detected laps
    # already describe, then equal parts when that terrain is missing or does
    # not match the workout's own ascent. The stored elevations are the
    # canonical filtered profile, so nothing is smoothed twice.
    def course(context)
      total = workout.distance.to_f
      plan = Allure::Insights::CoursePlan.terrain(total:, detected: context.dig(:laps, :detected) || {})
      if plan
        measured = profile.call(boundaries: plan.boundaries)
        return Allure::Insights::Course.new(plan:, result: measured) if measured && terrain_trusted?(measured)
      end

      plan = Allure::Insights::CoursePlan.parts(total:)
      return unless plan

      measured = profile.call(boundaries: plan.boundaries)
      measured && Allure::Insights::Course.new(plan:, result: measured)
    end

    def profile
      @profile ||= Allure::Gpx::RouteProfile.new(
        segments: workout.track_segments.to_a,
        workout_started_at: workout.started_at,
        stopped_speed_threshold_km_h: workout.sport.stopped_speed_threshold,
        elevation_filter: workout.elevation_filter,
        grade_adjusted_pace: workout.sport.grade_adjusted_pace?
      )
    end

    def terrain_trusted?(result)
      return false if result.sections.any? { it.elevation_coverage < SECTION_COVERAGE }

      expected = workout.ascent.to_f
      return true unless expected.positive?

      computed = result.sections.sum { it.ascent.to_f }
      (expected - computed).abs <= [ ASCENT_TOLERANCE * expected, ASCENT_FLOOR ].max
    end
  end
end
