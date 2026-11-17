# frozen_string_literal: true

module Workouts
  # Cancels the publication inside its safety delay (docs/dev/DELAYED-PUBLISHING.md
  # §4). Nothing was ever shared, so the row goes straight to the terminal
  # `deleted` state and no Delete activity is created; the media is purged by
  # Workouts::PublicationCleanup like any deleted publication.
  class ScheduledPublicationCancellation
    Result = Data.define(:publication, :cancelled)

    def initialize(user:, workout: nil, publication: nil, operator: false)
      @user = user
      @workout = workout
      @given_publication = publication
      @operator = operator
    end

    def call!
      publication = resolve_publication!
      authorize!(publication)
      return Result.new(publication:, cancelled: false) unless publication.scheduled?

      publication.with_lock do
        publication.reload
        next unless publication.scheduled?

        publication.mark_deleted!
        Webhooks::Events.publication_withdrawn(publication, reason: @operator ? "operator" : "cancelled")
        return Result.new(publication:, cancelled: true)
      end
      Result.new(publication:, cancelled: false)
    end

    private

    def resolve_publication!
      return @given_publication.reload if @given_publication
      raise ActiveRecord::RecordNotFound unless @workout

      @workout.reset_publications
      scheduled = @workout.scheduled_publications.to_a
      raise ArgumentError, "several scheduled publications: name the one to cancel" if scheduled.many?

      scheduled.first || raise(ActiveRecord::RecordNotFound)
    end

    def authorize!(publication)
      return if operator?

      owner_id = publication.workout&.user_id || publication.actor&.user_id
      raise ActiveRecord::RecordNotFound unless owner_id && owner_id == @user.id
    end

    def operator?
      @operator && @user.respond_to?(:instance_operator?) && @user.instance_operator?
    end
  end
end
