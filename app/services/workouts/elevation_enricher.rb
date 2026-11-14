# frozen_string_literal: true

module Workouts
  # Fetches the terrain elevation profile for one workout and caches it on
  # `workout_elevations`. Sampling and interpolation are pure
  # (`Allure::Elevation`); this service owns the provider conversation, the
  # throttle, and the persisted status. It never changes the analysis: applying
  # the cached profile is `Workouts::ApplyElevationSourceJob`'s job.
  class ElevationEnricher
    ALGORITHM_VERSION = WorkoutElevation::ALGORITHM_VERSION
    USABLE_STATUSES = %w[ready partial].freeze
    LAST_ERROR_LIMIT = 500

    class ProviderNotConfiguredError < StandardError; end

    Result = Data.define(:status, :samples_count, :requests_count)

    def initialize(workout:, client: nil, config: Allure::Elevation::Config, sleeper: nil)
      @workout = workout
      @config = config
      @client = client || config.client
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @requests = 0
    end

    def call
      raise ProviderNotConfiguredError, "no elevation provider configured" unless @config.configured?
      return existing_result if current?

      samples = samples_for(OriginalTrack.new(workout: @workout).call.segments)
      return persist(status: "unavailable", samples: [], last_error: nil) if samples.empty?

      elevations = fetch(samples)
      persist_samples(samples, elevations)
    rescue Allure::Elevation::OpenTopoData::Error => error
      persist_failure(error)
      raise
    end

    private

    def current?
      record = @workout.elevation
      return false unless record

      record.algorithm_version >= ALGORITHM_VERSION &&
        record.status.in?(USABLE_STATUSES) &&
        record.provider == @config.base_url &&
        record.dataset == @config.dataset
    end

    def existing_result
      record = @workout.elevation
      Result.new(status: record.status, samples_count: record.samples.length, requests_count: record.requests_count)
    end

    # A long route is sampled coarser so the workout never exceeds its provider
    # budget; the interval grows geometrically until the batches fit.
    def samples_for(segments)
      interval = @config.sample_metres
      distance = total_distance(segments)
      if distance.positive?
        limit = @config.max_requests_per_workout * Allure::Elevation::Sampler::MAX_LOCATIONS
        interval = [ interval, distance / limit ].max
      end

      samples = Allure::Elevation::Sampler.call(segments, interval_metres: interval)
      while Allure::Elevation::Sampler.chunks(samples).length > @config.max_requests_per_workout
        interval *= 1.5
        samples = Allure::Elevation::Sampler.call(segments, interval_metres: interval)
      end
      samples
    end

    def total_distance(segments)
      series = Allure::Elevation::TrackGeometry.cumulative_distances(segments)
      series.reverse.find(&:any?)&.last || 0.0
    end

    def fetch(samples)
      interval_seconds = 1.0 / @config.requests_per_second
      elevations = []

      Allure::Elevation::Sampler.chunks(samples).each_with_index do |chunk, index|
        @sleeper.call(interval_seconds) if index.positive?
        locations = chunk.map { |sample| [ sample.latitude, sample.longitude ] }
        elevations.concat(@client.elevations(locations))
        @requests += 1
      end

      elevations
    end

    def persist_samples(samples, elevations)
      rows = samples.zip(elevations).map do |sample, elevation|
        {
          "distance" => sample.distance,
          "latitude" => sample.latitude,
          "longitude" => sample.longitude,
          "elevation" => elevation&.round(1)
        }
      end
      usable = rows.count { |row| !row["elevation"].nil? }
      status = if usable.zero?
        "unavailable"
      elsif usable == rows.length
        "ready"
      else
        "partial"
      end

      persist(status:, samples: rows, last_error: nil)
    end

    def persist_failure(error)
      persist(status: "failed", samples: @workout.elevation&.samples || [], last_error: error.message.to_s.truncate(LAST_ERROR_LIMIT))
    rescue StandardError => persist_error
      Rails.error.report(
        persist_error, handled: false, context: { component: self.class.name, workout_id: @workout.id }
      )
    end

    def persist(status:, samples:, last_error:)
      record = @workout.elevation || @workout.build_elevation
      record.update!(
        status:,
        provider: @config.base_url,
        dataset: @config.dataset,
        algorithm_version: ALGORITHM_VERSION,
        samples:,
        requests_count: @requests,
        generated_at: Time.current,
        last_error:
      )
      Result.new(status:, samples_count: samples.length, requests_count: @requests)
    end
  end
end
