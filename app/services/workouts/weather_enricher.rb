# frozen_string_literal: true

module Workouts
  # Fetches and analyses the weather along one workout (docs/dev/WEATHER.md,
  # §5). Sampling, interpolation and the wind analysis are pure
  # (`Allure::Weather`); this service owns the provider conversation, the
  # daily budget, the pacing and the persisted row.
  #
  # The provider's raw hourly arrays are kept, so a run whose plan (cells,
  # hours, rounded elevations) did not change asks nothing again: a new
  # `ANALYSIS_VERSION`, or a re-analysis that leaves the cells alone,
  # converges offline.
  class WeatherEnricher
    FETCH_VERSION = 1
    # 2: the summary gains `temperature_mean`; 3: the series gains `day` and
    # the summary `is_day` (the icon's day or night variant).
    ANALYSIS_VERSION = 3
    LAST_ERROR_LIMIT = 500

    class BudgetExhaustedError < StandardError; end

    def initialize(workout:, client: nil, config: Allure::Weather::Config, sleeper: nil, now: nil)
      @workout = workout
      @config = config
      @client = client || config.client
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @now = now || -> { Time.current }
      @requests = 0
    end

    def call
      reason = WeatherEligibility.reason(@workout)
      return discard if WeatherEligibility::STRUCTURAL.include?(reason)
      return @workout.weather if reason

      points = Allure::Segments::PointStream.new(segments: @workout.track_segments, workout_started_at: @workout.started_at).call
      plan = Allure::Weather::Sampler.call(points)
      return unavailable("untimed") if plan.empty?

      samples = stored_samples(plan)
      endpoint, responses = reusable?(samples) ? [ record.endpoint, record.responses ] : fetch_with_fallback(plan)
      rows = Allure::Weather::Series.call(responses:, samples: plan.samples, cells: plan.cells)
      return unavailable("no_data") unless rows.any?(&:usable?)

      persist_ready(points:, plan:, samples:, endpoint:, responses:, rows:)
    rescue Allure::Weather::OpenMeteo::InvalidRequestError => error
      persist_failure(error)
    rescue Allure::Weather::OpenMeteo::UnavailableError => error
      record_error(error)
      raise
    end

    private

    def record
      @record ||= @workout.weather || @workout.build_weather
    end

    def stored_samples(plan)
      cells = plan.to_json_cells
      plan.to_json_samples.map { |sample| sample.merge(cells.fetch(sample["cell"])) }
    end

    def reusable?(samples)
      record.persisted? && record.fetch_version >= FETCH_VERSION && record.samples == samples &&
        record.endpoint.present? && record.responses.length == samples.map { |sample| sample["cell"] }.uniq.length
    end

    def fetch_with_fallback(plan)
      endpoint = @config.endpoint_for(@workout.started_at)
      responses = fetch(plan, endpoint)
      return [ endpoint.to_s, responses ] if complete?(plan, responses) || endpoint == :archive

      archived = fetch(plan, :archive)
      complete?(plan, archived) ? [ "archive", archived ] : [ endpoint.to_s, responses ]
    end

    def complete?(plan, responses)
      Allure::Weather::Series.complete?(
        Allure::Weather::Series.call(responses:, samples: plan.samples, cells: plan.cells)
      )
    end

    def fetch(plan, endpoint)
      chunks = plan.cells.each_slice(Allure::Weather::OpenMeteo::MAX_LOCATIONS).to_a
      check_budget!(chunks.length)

      chunks.each_with_index.flat_map do |cells, index|
        @sleeper.call(1.0 / @config.requests_per_second) if @requests.positive? || index.positive?
        @requests += 1
        request(endpoint, cells, plan)
      end
    end

    def request(endpoint, cells, plan)
      result = @client.hourly(endpoint:, locations: cells, start_date: plan.start_date, end_date: plan.end_date)
      count_request(endpoint, "ok")
      result
    rescue Allure::Weather::OpenMeteo::InvalidRequestError
      count_request(endpoint, "rejected")
      raise
    rescue Allure::Weather::OpenMeteo::UnavailableError
      count_request(endpoint, "unavailable")
      raise
    end

    def count_request(endpoint, result)
      Yabeda.allure.weather_requests_total.increment({ endpoint: endpoint.to_s, result: })
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "weather_requests_total" })
    end

    def check_budget!(needed)
      used = WorkoutWeather.fetched_since(@now.call - 24.hours).sum(:requests_count) + @requests
      return if used + needed <= @config.max_requests_per_day

      raise BudgetExhaustedError, "weather request budget exhausted (#{used}/#{@config.max_requests_per_day} in 24 h)"
    end

    def persist_ready(points:, plan:, samples:, endpoint:, responses:, rows:)
      exposure, = Allure::Weather::WindExposure.new(
        points:, rows:, stopped_speed_threshold_mps: @workout.sport.stopped_speed_threshold.to_f / 3.6
      ).call
      usable = rows.select(&:usable?)
      attributes = {
        status: "ready", fetch_version: FETCH_VERSION, analysis_version: ANALYSIS_VERSION, endpoint:,
        samples:, responses:, series: rows.map(&:to_h), exposure: exposure.to_h,
        summary: Allure::Weather::Summary.call(rows, exposure), unavailable_reason: nil, last_error: nil
      }
      if @requests.positive?
        attributes[:requests_count] = @requests
        attributes[:fetched_at] = @now.call
      end

      WorkoutWeather.transaction do
        record.update!(attributes)
        @workout.update_columns(weather_start: usable.first.to_h, weather_end: usable.last.to_h)
      end
      record
    end

    def discard
      @workout.weather&.destroy!
      @workout.update_columns(weather_start: nil, weather_end: nil) if @workout.weather_start || @workout.weather_end
      nil
    end

    def unavailable(reason)
      WorkoutWeather.transaction do
        record.update!(
          status: "unavailable", unavailable_reason: reason, last_error: nil, series: [], exposure: {}, summary: {},
          fetch_version: FETCH_VERSION, analysis_version: ANALYSIS_VERSION,
          **(@requests.positive? ? { requests_count: @requests, fetched_at: @now.call } : {})
        )
        @workout.update_columns(weather_start: nil, weather_end: nil)
      end
      record
    end

    def persist_failure(error)
      record.update!(status: "failed", last_error: error.message.to_s.truncate(LAST_ERROR_LIMIT),
                     **(@requests.positive? ? { requests_count: @requests, fetched_at: @now.call } : {}))
      record
    end

    def record_error(error)
      return unless record.persisted?

      record.update_columns(last_error: error.message.to_s.truncate(LAST_ERROR_LIMIT), updated_at: Time.current,
                            **(@requests.positive? ? { requests_count: record.requests_count + @requests, fetched_at: @now.call } : {}))
    end
  end
end
