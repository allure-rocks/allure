# frozen_string_literal: true

module Workouts
  class PublicationPolicy
    RESOURCES = %i[workout analysis map track chart media gpx route_image photos like react comment].freeze

    def initialize(publication:, principal:)
      @publication = publication
      @principal = principal
    end

    def allowed?(resource: :workout)
      return false unless RESOURCES.include?(resource.to_sym)
      return false unless @publication&.active?
      return false if @principal.actor&.tombstoned?
      return false if owner_deletion_scheduled?
      return false unless audience_allowed?

      resource_allowed?(resource.to_sym)
    rescue ActiveRecord::RecordNotFound, KeyError, NoMethodError, TypeError
      false
    end

    private

    # A public publication serves every signed-in account and the public wire
    # protocol, but never an anonymous browser visitor: public means
    # registered locally (PLAN_MEMBERS_ONLY.md). A followers publication serves
    # the owner and an accepted local follower whatever the switches say, and
    # an accepted remote follower whose locally assigned capability is
    # promoted only while restricted federation is enabled; the remote request
    # itself was signature-verified before this principal was built.
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

    # A deactivated owner's publications are refused to everyone until the
    # purge withdraws them (PLAN_ACCOUNT.md §4.2).
    def owner_deletion_scheduled? = @publication.actor&.user&.deletion_scheduled? || false

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
      workout = @publication.workout
      return false unless workout

      case @principal.kind
      when :browser_user
        @principal.user&.id == workout.user_id
      when :local_actor
        @principal.actor&.user_id == workout.user_id
      else
        false
      end
    end

    def public_publication? = @publication.audience == "public"

    def resource_allowed?(resource)
      case resource
      when :workout, :like
        true
      when :react
        # The owner reads the counts but never reacts to their own workout
        # (PLAN_REACTIONS.md §4.4); `:like` stays the inbound ActivityPub gate.
        !owner?
      when :comment
        # Unlike a reaction, the owner takes part in the thread; everyone the
        # audience serves may write while comments are open (PLAN_COMMENTS.md
        # §4.1).
        @publication.comments_open?
      when :analysis
        @publication.metrics.any?
      when :map, :track
        @publication.profile_settings["route"] == true && @publication.track.is_a?(Hash)
      when :chart
        chart = @publication.representation["chart"]
        chart.is_a?(Array) && chart.any?
      when :media
        %i[gpx route_image].any? { |attachment| attachment_allowed?(attachment) }
      when :gpx, :route_image
        attachment_allowed?(resource)
      when :photos
        # The frozen photo copies (PLAN_PHOTOS.md §5.4): only what the
        # snapshot shared, whatever the profile says today.
        @publication.profile_settings["photos"] == true && @publication.representation["photos"].is_a?(Array)
      else
        false
      end
    end

    def attachment_allowed?(resource)
      return false unless @publication.profile_settings[resource.to_s] == true

      attachment = if resource.to_sym == :route_image
        @publication.route_image_variant(:light)
      else
        @publication.sanitized_attachment(resource)
      end
      attachment.present?
    end
  end
end
