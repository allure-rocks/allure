# frozen_string_literal: true

module Segments
  # Stores the frozen elevation profile of one segment from its source workout.
  # Only the backfill sweep enqueues it: a normally created segment already
  # carries its profile, and an existing one is left alone once built.
  class BuildElevationProfileJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(segment)
      return if segment.elevation_profile.present?

      profile = ElevationProfileBuilder.new(segment:).call
      segment.update_columns(elevation_profile: profile)
    rescue StandardError => error
      Rails.error.report(error, handled: false, context: { component: self.class.name, segment_id: segment.id })
      raise
    end
  end
end
