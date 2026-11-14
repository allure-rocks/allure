# frozen_string_literal: true

module Segments
  # The single authorization boundary for a course publication: the public
  # protocol GETs, their media, and the signed followers-only branch
  # (PLAN_SEGMENTS_FEDERATION.md §9.2). The local HTML course page stays
  # governed by `Segment#viewable_by?`; this policy answers protocol
  # principals.
  class PublicationPolicy
    RESOURCES = %i[segment track media gpx route_image].freeze

    def initialize(publication:, principal:)
      @publication = publication
      @principal = principal
    end

    def allowed?(resource: :segment)
      resource = resource.to_sym
      return false unless RESOURCES.include?(resource)
      return false unless @publication&.active?
      return false if @principal.actor&.tombstoned?
      return false if @publication.actor&.user&.deletion_scheduled?
      return false unless audience_allowed?

      resource_allowed?(resource)
    rescue ActiveRecord::RecordNotFound, KeyError, NoMethodError, TypeError
      false
    end

    private

    # Public courses are readable by every signed-in account and by the public
    # wire protocol, but never by an anonymous browser visitor: public means
    # registered locally (PLAN_MEMBERS_ONLY.md). Followers-only courses serve
    # the owner and an accepted local follower whatever the switches say, and
    # an accepted remote follower whose locally assigned capability is
    # promoted only while restricted federation is enabled; the request itself
    # was signature-verified before this principal was built.
    def audience_allowed?
      if public_publication?
        case @principal.kind
        when :browser_user, :protocol_anonymous, :remote_actor then true
        when :local_actor then owner?
        else false
        end
      elsif followers_publication?
        followers_audience_allowed?
      else
        false
      end
    end

    def followers_audience_allowed?
      return true if owner?
      return false unless accepted_follower?

      case @principal.kind
      when :browser_user, :local_actor then true
      when :remote_actor then Allure::Federation::Config.restricted_enabled? && promoted_capability?
      else false
      end
    end

    def followers_publication? = @publication.audience == "followers"
    def public_publication? = @publication.audience == "public"

    def follower_actor
      case @principal.kind
      when :browser_user then @principal.user&.actor
      when :local_actor, :remote_actor then @principal.actor
      end
    end

    def accepted_follower?
      actor = follower_actor
      return false unless actor && !actor.tombstoned?

      Following.accepted_between(follower_actor: actor, followed_actor: @publication.actor).exists?
    end

    def promoted_capability?
      follower_actor&.capability_profile.in?(%w[restricted_fetch restricted_shared_inbox])
    end

    def owner?
      segment = @publication.segment
      return false unless segment

      case @principal.kind
      when :browser_user
        @principal.user&.id == segment.user_id
      when :local_actor
        @principal.actor&.user_id == segment.user_id
      else
        false
      end
    end

    def resource_allowed?(resource)
      case resource
      when :segment, :track
        @publication.track.is_a?(Hash)
      when :media
        %i[gpx route_image].any? { |attachment| attachment_allowed?(attachment) }
      when :gpx, :route_image
        attachment_allowed?(resource)
      else
        false
      end
    end

    def attachment_allowed?(resource)
      attachment = if resource.to_sym == :route_image
        @publication.route_image_variant(:light)
      else
        @publication.sanitized_attachment(resource)
      end
      attachment.present?
    rescue ArgumentError
      false
    end
  end
end
