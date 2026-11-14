# frozen_string_literal: true

module Federation
  # The presentation boundary for a received course: the remote page, its
  # track, and its cached media. A public course is visible to any signed-in
  # account; a followers-only course requires an active entitlement. Anonymous
  # visitors never see a remote copy (PLAN_SEGMENTS_FEDERATION.md §12.2).
  class RemoteSegmentPolicy
    RESOURCES = %i[segment track media].freeze

    def initialize(segment:, principal:)
      @segment = segment
      @principal = principal
    end

    def allowed?(resource: :segment)
      resource = resource.to_sym
      return false unless RESOURCES.include?(resource)
      return false unless @segment&.active?
      return false if @principal.kind == :anonymous
      return false unless @segment.public? || entitled?

      resource_allowed?(resource)
    rescue ActiveRecord::RecordNotFound, KeyError, NoMethodError, TypeError
      false
    end

    private

    def resource_allowed?(resource)
      case resource
      when :segment, :media
        true
      when :track
        track = @segment.representation["track"]
        track.is_a?(Hash) && Array(track["features"]).any?
      else
        false
      end
    end

    def entitled?
      actor = case @principal.kind
      when :browser_user then @principal.user&.actor
      when :local_actor then @principal.actor
      end
      return false unless actor

      @segment.entitled_to?(actor)
    end
  end
end
