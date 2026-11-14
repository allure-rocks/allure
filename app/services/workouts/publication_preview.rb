# frozen_string_literal: true

module Workouts
  # Owner-scoped, read-only candidate preview. Runs the exact projection and
  # privacy services publishing uses, without persisting anything: no
  # publication, no identity, no outbox event, no blob, no downloadable file.
  class PublicationPreview
    Result = Data.define(
      :ready, :blocking_error, :warnings, :candidate, :profile, :workout
    ) do
      def ready? = ready
    end

    def initialize(user:, workout:, profile:)
      @user = user
      @workout = workout
      @profile = profile
    end

    # Media probes run without persisting blobs. An included GPX/image that fails
    # to generate blocks publishing (the real publisher would fail the same
    # way), so readiness is false while still returning the candidate details
    # for the UI to explain what is not ready.
    def call
      candidate = PublicationCandidate.new(user: @user, workout: @workout, profile: @profile)
        .prepare!(persist_media: false)
      warnings = []
      warnings << :no_interior_points unless candidate.filtered.interior_points_removed?
      warnings.concat(endpoint_visibility_warnings(candidate.endpoint_coverage, candidate.endpoint_visibility))
      ready = media_ready?(candidate)
      Result.new(ready:, blocking_error: nil, warnings:, candidate:, profile: @profile, workout: @workout)
    rescue PublicationCandidate::PreparationError => error
      Result.new(ready: false, blocking_error: error.message, warnings: [], candidate: nil, profile: @profile, workout: @workout)
    end

    private

    # Mirrors Workouts::PublicationReadiness: an endpoint the profile leaves
    # unmasked stays visible even inside an active zone.
    def endpoint_visibility_warnings(coverage, visibility)
      settings = @profile.settings
      warnings = []
      if settings["mask_start"] != true && coverage&.dig(:start) && visibility&.dig(:start)
        warnings << :endpoint_visible_start
      end
      if settings["mask_finish"] != true && coverage&.dig(:finish) && visibility&.dig(:finish)
        warnings << :endpoint_visible_finish
      end
      warnings
    end

    def media_ready?(candidate)
      readiness = candidate.media_readiness || {}
      readiness.values.all? do |entry|
        !entry["included"] || entry["ready"]
      end
    end
  end
end
