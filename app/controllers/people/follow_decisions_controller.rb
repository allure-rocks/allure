# frozen_string_literal: true

module People
  # Accepts or rejects one inbound follow request. Authorization is the
  # followed local actor: a decision is only reachable by its owner.
  # A local request is decided whatever FEDERATION_ENABLED says; a remote
  # one only while federation is on, since its answer is an activity.
  class FollowDecisionsController < ApplicationController
    def update
      local_actor = Federation::ActorProvisioner.new(user: current_user).call!
      following = Following.where(followed_actor: local_actor).find(params[:id])
      raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled? || following.follower_actor.local?
      decision = params[:decision].to_s

      Federation::FollowDecision.new(following:, decision:).call!
      redirect_to people_path, notice: t("people.decisions.#{decision}.success")
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue Federation::FollowDecision::InvalidDecision
      redirect_to people_path, alert: t("people.decisions.invalid")
    end
  end
end
