# frozen_string_literal: true

module Participations
  # A confirmed or withdrawn participation changes who the assistant may name
  # in a summary (docs/dev/AI.md §3.1, §6). Confirming schedules the affected
  # workouts; withdrawing first drops a summary that carries a company fact,
  # so a name cannot outlive the confirmation while the regeneration waits.
  class SummaryRefresh
    # A confirmation that lands while a generation is already running cannot
    # change that answer: the job computed its facts before. One recheck after
    # the longest plausible generation picks the change up (AI.md §6).
    RECHECK = 5.minutes

    class << self
      def confirmed!(participation) = new(participation).confirmed!
      def withdrawn!(participation) = new(participation).withdrawn!
    end

    def initialize(participation)
      @participation = participation
    end

    def confirmed!
      workouts.each do |workout|
        was_pending = workout.assistant_summary&.pending?
        Workouts::SummaryRefresh.schedule(workout, bypass_window: true)
        recheck(workout) if was_pending
      end
    end

    def withdrawn!
      workouts.each do |workout|
        summary = workout.assistant_summary
        if summary && company_fact?(summary)
          summary.destroy!
          workout.association(:assistant_summary).reset
        end
        Workouts::SummaryRefresh.schedule(workout, bypass_window: true)
      end
    end

    private

    attr_reader :participation

    # A confirmation commonly arrives while the summary of the same workout is
    # still being written, and `schedule` leaves a pending row alone: without
    # this second look the summary would keep the facts of the moment before.
    def recheck(workout)
      return unless workout.assistant_summary&.pending?

      Workouts::GenerateSummaryJob.set(wait: RECHECK).perform_later(workout)
    end

    # A credit names the source workout on both sides; a link adds the
    # participant's own recording, whose summary may name the source owner.
    def workouts
      list = [ participation.workout ]
      list << participation.participant_workout if participation.kind == "link"
      list.compact.uniq
    end

    def company_fact?(summary)
      Array(summary.facts).any? { |fact| (fact["kind"] || fact[:kind]).to_s == "company" }
    end
  end
end
