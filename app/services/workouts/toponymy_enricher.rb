# frozen_string_literal: true

require "timeout"

module Workouts
  class ToponymyEnricher
    ALGORITHM_VERSION = 9
    # The version whose stored samples a selection-only change may be
    # re-derived from; any other version is re-geocoded in full.
    RESELECTABLE_VERSION = 8
    GEOCODING_TIMEOUT = 5.minutes
    LOCAL_DETAIL_MAX_DISTANCE = 30_000.0
    CENTER_LOOKUP_LIMIT = 16
    CENTER_LOOKUP_PRIORITY = %w[
      locality hamlet isolated_dwelling neighbourhood suburb village town city municipality
    ].freeze
    LOCAL_FEATURE_KINDS = %w[
      isolated_dwelling locality neighbourhood suburb hamlet route landmark hut viewpoint waterfall spring cave pass summit
    ].freeze

    def initialize(workout:, client: :default, sleeper: Kernel.method(:sleep), clock: nil,
                   request_interval: Allure::Toponyms::Config.request_interval)
      @workout = workout
      @client = client == :default ? default_client : client
      @sleeper = sleeper
      @request_interval = request_interval
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @last_request_started = nil
      @center_cache = {}
    end

    def call(force: false)
      # A virtual sport rendered a fictional world at a real anchor; reverse
      # geocoding it would name a place the athlete never visited
      # (docs/dev/VIRTUAL-PLATFORMS.md). The venue catalog names its place instead.
      return discard_virtual_toponymy if @workout.sport.virtual?

      toponymy = prepare_toponymy
      return toponymy if !force && toponymy.algorithm_version == ALGORITHM_VERSION &&
        %w[ready partial unavailable].include?(toponymy.status)
      return toponymy if !force && reselect_stored(toponymy)

      unless @client
        toponymy.update!(status: "unavailable", provider: nil, last_error: nil)
        return toponymy
      end

      samples = Allure::Toponyms::SampleTrack.new(segments: @workout.track_segments).call
      if samples.empty?
        toponymy.update!(status: "unavailable", sampled_points_count: 0, last_error: nil)
        return toponymy
      end

      results = nil
      builder = nil
      candidates = nil
      centers = nil
      Timeout.timeout(
        GEOCODING_TIMEOUT,
        Allure::Toponyms::Nominatim::UnavailableError,
        "Toponymy enrichment exceeded its time limit"
      ) do
        results = geocode(samples)
        builder = Allure::Toponyms::CandidateBuilder.new(samples:, results:)
        centers = endpoint_centers(samples, results)
        candidates = locate_centers(builder.call, samples)
      end
      context = builder.route_context(total_distance: @workout.distance, centers:)
      markers = Allure::Toponyms::Selector.new(
        candidates:,
        total_distance: @workout.distance,
        start_name: context.dig(:start, :name),
        finish_name: context.dig(:finish, :name)
      ).call
      successful = results.count(&:present?)

      status = if successful.zero?
        "failed"
      elsif successful == results.length
        "ready"
      else
        "partial"
      end

      toponymy.update!(
        status:,
        algorithm_version: ALGORITHM_VERSION,
        provider: @client.base_url,
        samples: samples.zip(results).map { |sample, result| stored_sample(sample, result) },
        start_place: context.fetch(:start) || {},
        finish_place: context.fetch(:finish) || {},
        markers:,
        sampled_points_count: samples.length,
        generated_at: Time.current,
        last_error: successful.zero? ? "No geocoding response was usable" : nil
      )
      name_laps(toponymy)
      name_places
      toponymy
    rescue StandardError => error
      status = error.is_a?(Allure::Toponyms::Nominatim::UnavailableError) ? "pending" : "failed"
      toponymy&.update_columns(status:, last_error: error.message.to_s.truncate(500), updated_at: Time.current)
      raise
    end

    private

    def discard_virtual_toponymy
      @workout.toponymy&.destroy!
      nil
    end

    def name_laps(toponymy)
      return unless toponymy.ready? || toponymy.partial?

      Laps::Naming.new(workout: @workout).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    # The workout-level place list is a pure assembly of what was just stored;
    # no additional geocoding request is ever made for it.
    def name_places
      Workouts::PlaceNamer.new(workout: @workout).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    # Version 9 changed the endpoint selection only: a version-8 toponymy whose
    # stored samples still line up with the stored track is re-selected
    # offline, with just the endpoint settlements' centres resolved
    # (docs/dev/WORKOUT.md). Every other case falls through to a full
    # re-geocoding, so the backfill never re-issues a reverse request per
    # sample.
    def reselect_stored(toponymy)
      selection = reselect_selection(toponymy)
      return false unless selection

      start_place, finish_place, markers, results = selection
      successful = results.count(&:present?)

      toponymy.update_columns(
        status: successful == results.length ? "ready" : "partial",
        start_place:, finish_place:, markers:,
        algorithm_version: ALGORITHM_VERSION,
        last_error: nil,
        generated_at: Time.current,
        updated_at: Time.current
      )
      name_laps(toponymy)
      name_places
      true
    end

    # [start_place, finish_place, markers, results] re-derived from the stored
    # samples, or nil when they cannot be reused.
    def reselect_selection(toponymy)
      return nil unless @client
      return nil unless toponymy.algorithm_version == RESELECTABLE_VERSION
      return nil unless toponymy.samples.present?

      stored = Array(toponymy.samples)
      samples = Allure::Toponyms::SampleTrack.new(segments: @workout.track_segments).call
      return nil unless samples.length == stored.length && aligned?(samples, stored)

      results = stored.map { |row| row_value(row, "result") }
      return nil if results.first.blank? || results.last.blank?

      centers = endpoint_centers(samples, results)
      context = Allure::Toponyms::CandidateBuilder.new(samples:, results:).route_context(
        total_distance: @workout.distance, centers:
      )
      start_place = context.fetch(:start) || {}
      finish_place = context.fetch(:finish) || {}

      [ start_place, finish_place, prune_endpoint_markers(toponymy.markers, start_place, finish_place), results ]
    end

    def aligned?(samples, stored)
      samples.zip(stored).all? do |sample, row|
        distance = row_value(row, "distance")
        distance.is_a?(Numeric) &&
          (distance.to_f - sample.fetch(:distance).to_f).abs < 0.05 &&
          row_value(row, "role").to_s == sample.fetch(:role).to_s
      end
    end

    def row_value(row, key)
      return nil unless row.respond_to?(:to_h)

      value = row.to_h
      value[key.to_s] || value[key.to_sym]
    end

    # The stored markers were chosen under the previous endpoint names; one
    # that now carries an endpoint's name would show twice on the profile.
    def prune_endpoint_markers(markers, *places)
      endpoint_names = places.filter_map { |place| row_value(place, "name").presence }.map { |name| normalized_name(name) }
      return Array(markers) if endpoint_names.empty?

      Array(markers).reject { |marker| endpoint_names.include?(normalized_name(row_value(marker, "name"))) }
    end

    # Endpoint settlement centres, resolved from the endpoint's own viewbox and
    # shared through `@center_cache` with `locate_centers`, so a settlement is
    # looked up at most once per run.
    def endpoint_centers(samples, results)
      [ [ samples.first, results.first ], [ samples.last, results.last ] ].flat_map do |sample, result|
        next [] unless sample.is_a?(Hash) && result.is_a?(Hash)

        endpoint_settlements(result).filter_map do |entry|
          center = center_for(
            name: entry.fetch(:name), kind: entry.fetch(:kind),
            longitude: sample[:longitude], latitude: sample[:latitude],
            ancestors: entry[:ancestors]
          )
          next unless center

          {
            name: entry.fetch(:name), kind: entry.fetch(:kind),
            latitude: center.fetch(:center_latitude), longitude: center.fetch(:center_longitude)
          }
        end
      end
    end

    def endpoint_settlements(result)
      Array(result[:hierarchy] || result["hierarchy"]).filter_map do |entry|
        next unless entry.is_a?(Hash)

        value = entry.to_h.symbolize_keys
        kind = value[:kind].to_s
        next unless Allure::Toponyms::Settlements::KINDS.include?(kind)
        next if value[:name].to_s.strip.blank?

        value.merge(kind:)
      end
    end

    def prepare_toponymy
      @workout.with_lock do
        @workout.toponymy || @workout.create_toponymy!(
          status: "pending",
          algorithm_version: ALGORITHM_VERSION
        )
      end
    rescue ActiveRecord::RecordNotUnique
      @workout.association(:toponymy).reload
    end

    def default_client
      base_url = Allure::Toponyms::Config.base_url
      Allure::Toponyms::Nominatim.new(base_url:) if base_url
    end

    def geocode(samples)
      samples.map { geocode_sample(it) }
    end

    def geocode_sample(sample)
      zoom = sample[:role] == "climb_summit" ? Allure::Toponyms::Nominatim::SUMMIT_ZOOM : Allure::Toponyms::Nominatim::MARKER_ZOOM
      result = throttled_reverse(sample, zoom)
      return result unless needs_local_detail?(sample, result)

      result = merge_results(result, throttled_reverse(sample, Allure::Toponyms::Nominatim::LOCALITY_ZOOM))
      return result unless broad_result?(result)

      merge_results(result, throttled_reverse(sample, Allure::Toponyms::Nominatim::ROUTE_ZOOM))
    end

    def local_detail?(sample)
      @workout.distance.to_f <= LOCAL_DETAIL_MAX_DISTANCE && sample[:role] != "climb_summit"
    end

    def needs_local_detail?(sample, result)
      local_detail?(sample) && (broad_result?(result) || distant_result?(result, sample))
    end

    def broad_result?(result)
      feature = result&.dig(:feature)
      feature.nil? || !LOCAL_FEATURE_KINDS.include?(feature[:kind].to_s)
    end

    def distant_result?(result, sample)
      feature = result&.dig(:feature)
      return false unless feature.is_a?(Hash)

      limit = Allure::Toponyms::Settlements::CENTER_DISTANCE_LIMIT[feature[:kind].to_s]
      latitude = feature[:center_latitude]
      longitude = feature[:center_longitude]
      return false unless limit && latitude.is_a?(Numeric) && longitude.is_a?(Numeric)

      Allure::Toponyms::Distance.metres(latitude, longitude, sample.fetch(:latitude), sample.fetch(:longitude)) > limit
    end

    def merge_results(base, detailed)
      return base unless detailed
      return detailed unless base

      hierarchy = (Array(detailed[:hierarchy]) + Array(base[:hierarchy])).uniq do |place|
        [ normalized_name(place[:name]), place[:kind].to_s ]
      end
      { feature: detailed[:feature] || base[:feature], hierarchy: }
    end

    def throttled_reverse(sample, zoom)
      throttled do
        @client.reverse(
          longitude: sample.fetch(:longitude),
          latitude: sample.fetch(:latitude),
          zoom:
        )
      end
    end

    def throttled
      if @last_request_started
        wait = @request_interval - (@clock.call - @last_request_started)
        @sleeper.call(wait) if wait.positive?
      end
      @last_request_started = @clock.call
      yield
    end

    def locate_centers(candidates, samples)
      lookup_candidates = candidates.select do |candidate|
        Allure::Toponyms::Settlements::KINDS.include?(candidate[:kind].to_s) && candidate[:center_latitude].nil?
      end.sort_by do |candidate|
        [ CENTER_LOOKUP_PRIORITY.index(candidate[:kind].to_s) || CENTER_LOOKUP_PRIORITY.length,
          -candidate.fetch(:occurrences, 1), candidate.fetch(:coverage, 0), candidate.fetch(:distance) ]
      end.first(CENTER_LOOKUP_LIMIT)

      lookup_candidates.each do |candidate|
        center = center_for(
          name: candidate.fetch(:name), kind: candidate.fetch(:kind),
          longitude: candidate.fetch(:route_longitude), latitude: candidate.fetch(:route_latitude),
          ancestors: candidate[:ancestors]
        )
        candidate.merge!(center) if center
      end

      candidates.map { project_center(it, samples) }
    end

    def center_for(name:, kind:, longitude:, latitude:, ancestors: [])
      key = [ normalized_name(name), kind.to_s ]
      @center_cache.fetch(key) do
        @center_cache[key] = lookup_center(name:, kind:, longitude:, latitude:, ancestors:)
      end
    end

    def lookup_center(name:, kind:, longitude:, latitude:, ancestors:)
      return unless @client.respond_to?(:settlement_center)

      throttled do
        @client.settlement_center(name:, kind:, longitude:, latitude:, ancestors:)
      end
    end

    def project_center(candidate, samples)
      latitude = candidate[:center_latitude]
      longitude = candidate[:center_longitude]
      limit = Allure::Toponyms::Settlements::CENTER_DISTANCE_LIMIT[candidate[:kind].to_s]
      return candidate unless latitude.is_a?(Numeric) && longitude.is_a?(Numeric) && limit

      nearby_samples = samples.select do |sample|
        sample.fetch(:distance).between?(
          candidate.fetch(:passage_start) - limit,
          candidate.fetch(:passage_finish) + limit
        )
      end
      nearest = nearby_samples.min_by do |sample|
        Allure::Toponyms::Distance.metres(latitude, longitude, sample.fetch(:latitude), sample.fetch(:longitude))
      end
      return candidate unless nearest

      center_distance = Allure::Toponyms::Distance.metres(
        latitude, longitude, nearest.fetch(:latitude), nearest.fetch(:longitude)
      )
      projected = candidate.merge(center_distance: center_distance.round(1))
      return projected if center_distance > limit

      projected.merge(distance: nearest.fetch(:distance), elevation: nearest[:elevation], near_center: true)
    end

    def normalized_name(name)
      I18n.transliterate(name.to_s).downcase.strip
    end

    def stored_sample(sample, result)
      sample.slice(:distance, :elevation, :role, :climb_gain, :climb_prominence).merge(result: result || {})
    end
  end
end
