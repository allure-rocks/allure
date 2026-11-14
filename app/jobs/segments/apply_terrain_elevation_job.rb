# frozen_string_literal: true

module Segments
  # Gives one course the terrain service's elevation figures
  # (`Segments::TerrainElevation`). An unreachable provider retries; a refused
  # request or exhausted retries mark the course `failed`, which the operator's
  # backfill tries again.
  class ApplyTerrainElevationJob < ApplicationJob
    queue_as :default
    limits_concurrency key: ->(segment) { "segment-terrain-elevation-#{segment.id}" }, duration: 10.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    retry_on Allure::Elevation::OpenTopoData::UnavailableError, wait: :polynomially_longer, attempts: 5
    discard_on Allure::Elevation::OpenTopoData::InvalidRequestError
    discard_on TerrainElevation::ProviderNotConfiguredError
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    after_discard do |job, error|
      segment = job.arguments.first
      if segment.is_a?(Segment) && error.is_a?(Allure::Elevation::OpenTopoData::Error)
        segment.update_columns(elevation_status: "failed", updated_at: Time.current)
      end
    end

    # Enqueued after a course is created or changes visibility; ineligible
    # courses cost nothing.
    def self.enqueue_if_eligible(segment)
      perform_later(segment) if TerrainElevation.eligible?(segment)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: name, segment_id: segment.id })
    end

    def perform(segment)
      TerrainElevation.new(segment:).call
    end
  end
end
