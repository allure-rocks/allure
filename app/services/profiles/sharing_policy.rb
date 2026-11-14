# frozen_string_literal: true

module Profiles
  # These live, local profile sections have their own audiences, independent
  # of publication permissions and the restricted-federation feature switch.
  class SharingPolicy
    def initialize(user:, viewer:)
      @user = user
      @viewer = viewer
    end

    def allowed?(audience:)
      return false unless @viewer.is_a?(User) && @viewer.persisted?
      return false if @user.deactivated? || @viewer.deactivated?

      case audience
      when "members" then true
      when "followers" then @viewer == @user || accepted_follower?
      else false
      end
    end

    private

    def accepted_follower?
      follower = @viewer.actor
      followed = @user.actor
      return false unless follower&.local? && followed&.local?
      return false if follower.tombstoned? || followed.tombstoned?

      Following.accepted_between(follower_actor: follower, followed_actor: followed).exists?
    end
  end
end
