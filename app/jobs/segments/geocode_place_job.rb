# frozen_string_literal: true

module Segments
  # Geocodes one course's nearby place (docs/dev/SEGMENTS.md). It shares the
  # workout toponymy's concurrency key, so the geocoding jobs this instance
  # runs at once stay within GEOCODING_CONCURRENCY.
  class GeocodePlaceJob < ApplicationJob
    queue_as :default
    limits_concurrency to: Allure::Toponyms::Config.concurrency,
                       key: ->(*) { "workout-toponymy-geocoding" }, duration: 20.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    retry_on Allure::Toponyms::Nominatim::UnavailableError, wait: :polynomially_longer, attempts: 5 do |job, _error|
      segment = job.arguments.first
      segment.update_columns(place_status: "failed", place_geocoded_at: Time.current) if segment.persisted?
    end
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(segment, force: false)
      PlaceGeocoder.new(segment:).call(force:)
    end
  end
end
