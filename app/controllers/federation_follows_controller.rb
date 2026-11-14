# frozen_string_literal: true

# The services refuse a remote target while federation is off, so a local
# follow works whatever FEDERATION_ENABLED says.
class FederationFollowsController < ApplicationController
  def create
    target = follow_params[:target]
    raise Federation::Follow::InvalidTarget if target.blank?

    following = Federation::Follow.new(user: current_user, target:).call!
    notice = following.accepted? ? t("federation_follow.create.local_success") : t("federation_follow.create.success")
    redirect_back fallback_location: root_path, notice:
  rescue Federation::Follow::InvalidTarget, Federation::Unfollow::InvalidTarget
    redirect_back fallback_location: root_path, alert: t("federation_follow.errors.invalid_target")
  end

  def destroy
    target = follow_params[:target]
    raise Federation::Unfollow::InvalidTarget if target.blank?

    Federation::Unfollow.new(user: current_user, target:).call!
    redirect_back fallback_location: root_path, notice: t("federation_follow.destroy.success")
  rescue Federation::Follow::InvalidTarget, Federation::Unfollow::InvalidTarget
    redirect_back fallback_location: root_path, alert: t("federation_follow.errors.invalid_target")
  end

  private

  def follow_params
    params.permit(:target)
  end
end
