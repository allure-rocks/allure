# frozen_string_literal: true

module Workouts
  # The single scheduling seam of a workout's assistant summary (docs/dev/AI.md
  # §6): it decides whether the facts changed, marks the row pending and
  # enqueues the generation. It never calls the model itself.
  class SummaryRefresh
    AUTO_WINDOW = 30.days
    COALESCE = 30.seconds

    class << self
      # `bypass_window` is for a participation change, not for an archive: a
      # name must not outlive a confirmation on an old workout, even though the
      # automatic window would have left that workout alone (AI.md §6).
      def schedule(workout, explicit: false, bypass_window: false) = new(workout, explicit:, bypass_window:).call

      # The day's provider calls, over the rows touched in the last 24 hours.
      def budget_exhausted?(now: Time.current)
        used = WorkoutSummary.where(updated_at: (now - 24.hours)..).sum(:requests_count)
        used >= Allure::Assistant::Config.max_requests_per_day
      end
    end

    def initialize(workout, explicit: false, bypass_window: false)
      @workout = workout
      @explicit = explicit
      @bypass_window = bypass_window
    end

    def call
      # An archive import must never queue months of model calls; only the
      # owner's explicit request and a participation change get past the
      # window. Checked before anything reads the account.
      return if !explicit && !bypass_window && workout.started_at < AUTO_WINDOW.ago
      return unless SummaryEligibility.eligible?(workout)

      row = workout.assistant_summary
      return if row&.pending?

      snapshot = SummaryFacts.new(workout).call
      if !explicit && row&.ready? && row.version == Allure::Insights::VERSION && row.facts_digest == snapshot.digest
        return
      end

      row ||= workout.build_assistant_summary
      row.assign_attributes(
        status: "pending",
        locale: snapshot.locale,
        version: Allure::Insights::VERSION,
        facts: snapshot.facts.map(&:to_h),
        facts_digest: snapshot.digest,
        last_error: nil
      )
      row.requested_at = Time.current if explicit
      row.save!
      GenerateSummaryJob.set(wait: COALESCE).perform_later(workout)
    end

    private

    attr_reader :workout, :explicit, :bypass_window
  end
end
