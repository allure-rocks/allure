# frozen_string_literal: true

# Bulk activity operations (docs/dev/BULK-ACTIONS.md, DESIGN.md §10.19, §20.4).
# The owner selects rows in the desktop table view: quick actions apply in the
# request; reviewable operations are frozen into a draft ledger and executed
# by Workouts::BulkOperationJob. Every lookup is owner-scoped and foreign
# identifiers are dropped without a hint; the endpoints make no user-agent
# distinction — the selection UI is simply never rendered in the iOS
# companion.
class WorkoutBulkOperationsController < ApplicationController
  before_action :set_operation, only: %i[show update cancel status]
  before_action :set_no_store, only: %i[show status]

  def apply
    return redirect_to(return_path, alert: t("workouts.bulk.errors.missing_action")) if params[:quick_operation].blank?

    ids = selection_ids
    return redirect_to(return_path, alert: t("workouts.bulk.errors.no_selection")) if ids.empty?

    result = Workouts::BulkQuickAction.new(
      user: current_user, workout_ids: ids, action: params[:quick_operation]
    ).call!
    redirect_to return_path, notice: quick_notice(result)
  rescue Workouts::BulkSelection::TooManyWorkouts
    redirect_to return_path, alert: too_many_message
  rescue Workouts::BulkQuickAction::InvalidAction
    redirect_to return_path, alert: t("workouts.bulk.errors.invalid_action")
  end

  # Freezes the reviewed selection: the operation page is the confirmation.
  def review
    operation = params[:operation].to_s
    return redirect_to(return_path, alert: t("workouts.bulk.errors.invalid_action")) unless WorkoutBulkOperation::OPERATIONS.include?(operation)

    ids = selection_ids
    return redirect_to(return_path, alert: t("workouts.bulk.errors.no_selection")) if ids.empty?

    record = WorkoutBulkOperation.start_draft!(
      user: current_user, operation:, workout_ids: ids, return_to: safe_return_to(params[:return_to])
    )
    redirect_to workout_bulk_operation_path(record)
  rescue Workouts::BulkSelection::TooManyWorkouts
    redirect_to return_path, alert: too_many_message
  end

  def show
    if @operation.draft?
      @report = Workouts::BulkReview.new(operation: @operation).call
      render :review
    else
      load_progress
    end
  end

  # The polled fragment of the progress page.
  def status
    load_progress
    render partial: "progress", locals: { operation: @operation, items: @items, counts: @counts, total: @total }
  end

  # Confirms a draft: parameters are validated, the row is queued, and the job
  # is enqueued. A lost enqueue returns the row to the draft instead of
  # stranding it in `queued`.
  def update
    @operation.confirm!(sport_id: params[:sport_id])
    begin
      Workouts::BulkOperationJob.perform_later(@operation.id, @operation.user_id)
    rescue StandardError => error
      @operation.update!(status: "draft", started_at: nil)
      Rails.error.report(error, handled: true,
        context: { component: self.class.name, workout_bulk_operation_id: @operation.id })
      return redirect_to workout_bulk_operation_path(@operation), alert: t("workouts.bulk.confirm.enqueue_failed")
    end
    redirect_to workout_bulk_operation_path(@operation), notice: t("workouts.bulk.confirm.queued")
  rescue WorkoutBulkOperation::NotDraft
    redirect_to workout_bulk_operation_path(@operation), alert: t("workouts.bulk.confirm.not_draft")
  rescue WorkoutBulkOperation::InvalidParameters
    @report = Workouts::BulkReview.new(operation: @operation).call
    @operation.errors.add(:sport, t("workouts.import.errors.missing_sport"))
    render :review, status: :unprocessable_content
  end

  def cancel
    @operation.cancel!
    redirect_to workout_bulk_operation_path(@operation), notice: t("workouts.bulk.cancel.requested")
  end

  private

  def set_operation
    @operation = current_user.workout_bulk_operations.find(params[:id])
  end

  def load_progress
    @items = @operation.items.in_order.includes(workout: :sport)
    @counts = @operation.progress_counts
    @total = @operation.total_count
  end

  def selection_ids
    Workouts::BulkSelection.new(user: current_user, params: params).ids
  end

  # French treats zero as singular, so an unchanged selection gets its own
  # sentence instead of a pluralized "1 activity" lie.
  def quick_notice(result)
    base = "workouts.bulk.notices.#{result.action}"
    return t("#{base}.none") if result.affected_count.zero?

    t(base, count: result.affected_count)
  end

  def too_many_message = t("workouts.bulk.errors.too_many", max: Workouts::BulkSelection::MAX_WORKOUTS)

  # The list the operation was started from, preserved across the request so
  # filters, page and view round-trip. Only local paths are accepted.
  def return_path
    safe_return_to(params[:return_to]) || workouts_path(view: "table")
  end

  def safe_return_to(value)
    path = value.to_s
    path.start_with?("/") && !path.start_with?("//") ? path : nil
  end

  def set_no_store
    response.set_header("Cache-Control", "no-store")
  end
end
