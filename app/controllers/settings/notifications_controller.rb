# frozen_string_literal: true

module Settings
  # In-app notification preferences (PLAN_NOTIFICATIONS.md). A disabled kind is
  # never created, so re-enabling it does not resurrect old events.
  class NotificationsController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(notifications_params)
        redirect_to settings_notifications_path, notice: t("settings.notifications.update.success")
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def notifications_params
      params.require(:user).permit(:notify_follow_requests, :notify_follow_accepted, :notify_publication_activated,
                                   :notify_auto_published, :notify_auto_publication_failed,
                                   :notify_reactions, :notify_comments, :notify_participation_requests,
                                   :notify_participation_confirmed, :notify_import_connections, :notify_webhooks,
                                   :together_detection_enabled)
    end
  end
end
