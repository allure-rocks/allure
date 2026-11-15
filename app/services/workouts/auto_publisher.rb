# frozen_string_literal: true

module Workouts
  # Settles a workout's waiting automatic publications (docs/dev/AUTO-PUBLISHING.md
  # §5). Nothing happens until every enrichment has settled; past the deadline
  # the rows fail and the owner is told to publish by hand. Once ready, each row
  # goes through `Workouts::Publisher` with its profile — the same privacy
  # preparation, refusals and safety delay as a publish by hand — unless the
  # profile was turned off, a publication already holds the audience, or the
  # workout became an excluded commute or sport in the meantime.
  #
  # Idempotent: only `waiting` rows are touched, and the job that calls it runs
  # one at a time per workout.
  class AutoPublisher
    def initialize(workout:, now: Time.current)
      @workout = workout
      @now = now
    end

    def call
      rows = @workout.auto_publications.waiting.includes(:publishing_profile).order(:id).to_a
      return if rows.empty?
      return if @workout.user.deactivated?

      I18n.with_locale(@workout.user.locale) do
        if AutoPublicationReadiness.new(@workout).ready?
          rows.each { |row| settle(row) }
        else
          rows.select { |row| row.overdue?(@now) }.each { |row| fail!(row, "enrichment_timeout") }
        end
      end
    end

    private

    def settle(row)
      row.reload
      return unless row.waiting?

      profile = row.publishing_profile
      return skip!(row, "profile_disabled") unless profile&.auto_publish? && profile.audience == row.audience
      return skip!(row, "profile_unavailable") unless profile.publishable?
      return skip!(row, "commute") if @workout.commute? && profile.auto_publish_exclude_commute?
      return skip!(row, "sport") if profile.auto_publish_excludes_sport?(@workout.sport)
      return skip!(row, "already_published") if @workout.workout_publications.live.exists?(audience: row.audience)

      publication = Publisher.new(user: @workout.user, workout: @workout, profile:).call!
      row.settle!("published", publication:, at: @now)
      notify_published(publication)
    rescue Publisher::PublicationError => error
      fail!(row, "publication_refused", detail: error.message)
    rescue ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished
      raise
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_auto_publication_id: row.id })
      fail!(row, "error")
    end

    def skip!(row, reason)
      row.settle!("skipped", reason:, at: @now)
    end

    def fail!(row, reason, detail: nil)
      row.settle!("failed", reason:, detail:, at: @now)
      Notifications::Create.new(
        user: @workout.user,
        kind: "auto_publication_failed",
        subject: row,
        payload: { "audience" => row.audience, "reason" => reason }
      ).call!
      Webhooks::Events.auto_publication_failed(row, reason:)
    end

    # Actorless, like the activation notice: the owner's own profile acted.
    def notify_published(publication)
      Notifications::Create.new(
        user: @workout.user,
        kind: "auto_published",
        subject: publication,
        payload: {
          "audience" => publication.audience,
          "scheduled_for" => (publication.scheduled_for&.iso8601 if publication.scheduled?)
        }.compact
      ).call!
    end
  end
end
