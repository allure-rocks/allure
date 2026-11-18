# frozen_string_literal: true

module Workouts
  # The single scheduling seam of a workout's assistant summary (docs/dev/AI.md
  # §6): it decides whether the facts changed, marks the row pending and
  # enqueues the generation. It never calls the model itself.
  class SummaryRefresh
    AUTO_WINDOW = 30.days
    COALESCE = 30.seconds

    class << self
      def schedule(workout, explicit: false) = new(workout, explicit:).call

      # The day's provider calls, over the rows touched in the last 24 hours.
      def budget_exhausted?(now: Time.current)
        used = WorkoutSummary.where(updated_at: (now - 24.hours)..).sum(:requests_count)
        used >= Allure::Assistant::Config.max_requests_per_day
      end
    end

    def initialize(workout, explicit: false)
      @workout = workout
      @explicit = explicit
    end

    def call
      # An archive import must never queue months of model calls; the owner's
      # explicit request is the only way past the window. Checked before
      # anything reads the account.
      return if !explicit && workout.started_at < AUTO_WINDOW.ago
      return unless SummaryEligibility.eligible?(workout)

      row = workout.assistant_summary
      return if row&.pending?

      snapshot = SummaryFacts.new(workout).call
      return if row&.ready? && row.version == Allure::Insights::VERSION && row.facts_digest == snapshot.digest

      row ||= workout.build_assistant_summary
      row.assign_attributes(
        status: "pending",
        locale: snapshot.locale,
        version: Allure::Insights::VERSION,
        facts: snapshot.facts.map(&:to_h),
        facts_digest: snapshot.digest,
        last_error: nil
      )
      row.save!
      GenerateSummaryJob.set(wait: COALESCE).perform_later(workout)
    end

    private

    attr_reader :workout, :explicit
  end
end
