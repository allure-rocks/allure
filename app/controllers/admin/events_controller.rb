# frozen_string_literal: true

module Admin
  # The operator audit log (PLAN_ADMIN.md §4.9, §5): every mutation, newest
  # first, filterable by action. Read-only.
  class EventsController < BaseController
    include Pagy::Method

    def index
      @kind = AdminEvent::ACTIONS.include?(params[:kind]) ? params[:kind] : nil
      scope = AdminEvent.recent_first.includes(:user)
      scope = scope.where(action: @kind) if @kind
      @pagy, @events = pagy(scope, limit: 50)
    end
  end
end
