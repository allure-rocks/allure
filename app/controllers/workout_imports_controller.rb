# frozen_string_literal: true

class WorkoutImportsController < ApplicationController
  before_action :set_batch, only: %i[show status cancel]
  # The manual entry panel (PLAN_MANUAL_ENTRY.md §5) renders with the page.
  before_action :set_manual_entry, only: %i[new create]
  # The database-counted admission below bounds what is stored; this keeps one
  # account from hammering the endpoint (PLAN_IMPORT_SOURCES.md §3.2).
  rate_limit to: 20, within: 1.hour, only: :create, by: -> { current_user.id }, name: "web-imports",
             with: -> { refuse_rate_limited }

  def new
    @batch = current_user.workout_import_batches.new
    @sports = Sport.catalog_order
  end

  def create
    @sports = Sport.catalog_order
    @batch = current_user.workout_import_batches.new(batch_params.except(:source_files, :equipment_ids))
    @batch.sport = Sport.find_by(id: batch_params[:sport_id])
    @batch.equipment_ids = owned_equipment_ids
    files = Array(batch_params[:source_files]).compact_blank

    if files.empty?
      @batch.errors.add(:source_files, t("workouts.batch_import.errors.missing_files"))
    elsif files.length > Workouts::ArchiveReader::MAX_SOURCE_FILES
      @batch.errors.add(:source_files, t("workouts.batch_import.errors.too_many_entries", max: Workouts::ArchiveReader::MAX_SOURCE_FILES))
    elsif files.sum { |file| file.size.to_i } > Workouts::ArchiveReader::MAX_SOURCE_BYTES
      @batch.errors.add(:source_files, t("workouts.batch_import.errors.source_too_large", max: "500 MB"))
    end
    @batch.errors.add(:sport, t("workouts.import.errors.missing_sport")) unless @batch.sport
    @batch.source_bytes = files.sum { |file| file.size.to_i }
    if @batch.errors.none? && (refusal = admission_refusal)
      @batch.errors.add(:source_files, refusal.message)
    end

    if @batch.errors.any?
      render :new, status: :unprocessable_content and return
    end

    WorkoutImportBatch.transaction do
      @batch.save!
      @batch.source_files.attach(files)
    end
    Workouts::ImportBatchJob.perform_later(@batch)
    redirect_to workout_import_path(@batch), notice: t("workouts.batch_import.create.success")
  rescue ActiveRecord::RecordInvalid
    @sports = Sport.catalog_order
    render :new, status: :unprocessable_content
  end

  def show
    @entries = @batch.entries.includes(workout: [ :sport, { auto_publications: :workout_publication } ]).order(:position)
  end

  def status
    @entries = @batch.entries.includes(workout: [ :sport, { auto_publications: :workout_publication } ]).order(:position)
    render partial: "status", locals: { batch: @batch, entries: @entries }
  end

  def cancel
    @batch.cancel!
    redirect_to workout_import_path(@batch), notice: t("workouts.batch_import.cancel.requested")
  end

  private

  def admission_refusal
    Workouts::ImportAdmission.new(user: current_user, source: @batch.source, bytes: @batch.source_bytes).refusal
  end

  def refuse_rate_limited
    @sports = Sport.catalog_order
    @batch = current_user.workout_import_batches.new
    @batch.errors.add(:source_files, t("workouts.batch_import.errors.rate_limited"))
    render :new, status: :too_many_requests
  end

  def set_manual_entry
    @manual_form = ManualWorkoutForm.blank(user: current_user)
    @equipments = current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
  end

  def set_batch
    @batch = current_user.workout_import_batches.find_by_short_id!(params[:id])
  end

  def batch_params
    params.fetch(:workout_import_batch, {}).permit(
      :sport_id,
      :notes,
      :title,
      :commute,
      source_files: [],
      equipment_ids: []
    )
  end

  # Only the account's own equipment, like the workout form: an unknown id is
  # ignored instead of raising (PLAN_IMPORT_SOURCES.md §2).
  def owned_equipment_ids
    ids = Array(batch_params[:equipment_ids]).reject(&:blank?)
    current_user.equipments.where(id: ids).ids
  end
end
