# frozen_string_literal: true

module Admin
  # Import failure inspection (PLAN_ADMIN.md §4.7): the batch overview, by
  # status and source, and the per-entry parser detail that until now was
  # only logged. The connections live in Admin::ImportConnectionsController.
  class ImportsController < BaseController
    include Pagy::Method

    def index
      @status = WorkoutImportBatch::STATUSES.include?(params[:status]) ? params[:status] : nil
      scope = WorkoutImportBatch.includes(:user).order(created_at: :desc, id: :desc)
      scope = scope.where(status: @status) if @status
      @source = WorkoutImportBatch::SOURCES.include?(params[:source]) ? params[:source] : nil
      scope = scope.where(source: @source) if @source
      @pagy, @batches = pagy(scope, limit: 25)
    end

    def show
      @batch = WorkoutImportBatch.find_by_short_id!(params[:id])
      @entries = @batch.entries.order(:position)
    end
  end
end
