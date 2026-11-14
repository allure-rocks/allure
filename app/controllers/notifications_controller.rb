# frozen_string_literal: true

# The signed-in in-app inbox (PLAN_NOTIFICATIONS.md): the topbar bell's badge
# and dropdown, the paginated list, and read state. Every lookup is scoped to
# the current account, so another account's notification is a 404.
class NotificationsController < ApplicationController
  include Pagy::Method

  def index
    @filter = params[:filter] == "unread" ? "unread" : "all"
    scope = current_user.notifications.recent_first.includes(:actor)
    scope = scope.unread if @filter == "unread"
    @pagy, @notifications = pagy(scope, limit: 20)
    @unread_count = current_user.notifications.unread.count
  end

  # Opening a notification reads it; the target is resolved from the kind and
  # degrades to the inbox when its actor is gone.
  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!
    redirect_to helpers.notification_target_path(@notification), status: :see_other
  end

  def badge
    set_no_store
    render partial: "notifications/badge", locals: { count: current_user.notifications.unread.count }
  end

  def menu
    set_no_store
    render partial: "notifications/menu", locals: {
      notifications: current_user.notifications.recent_first.includes(:actor).limit(5),
      unread_count: current_user.notifications.unread.count
    }
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_back fallback_location: notifications_path, notice: t("notifications.mark_all_read.success")
  end

  private

  def set_no_store
    response.set_header("Cache-Control", "no-store")
  end
end
