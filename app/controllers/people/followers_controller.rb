# frozen_string_literal: true

module People
  # docs/dev/PEOPLE.md: the followed account ends one accepted follow. The row
  # is scoped to the local actor that owns it, so another account's follower
  # is a 404.
  class FollowersController < ApplicationController
    def destroy
      local_actor = Federation::ActorProvisioner.new(user: current_user).call!
      following = Following.accepted.where(followed_actor: local_actor).find(params[:id])

      Federation::RemoveFollower.new(following:).call!
      redirect_to people_path(tab: "followers"), notice: t("people.followers.removed"), status: :see_other
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue Federation::RemoveFollower::InvalidTarget
      redirect_to people_path(tab: "followers"), alert: t("people.followers.remove_invalid"), status: :see_other
    end
  end
end
