# frozen_string_literal: true

# The Strava archive source (PLAN_STRAVA_ARCHIVE.md §8): one ZIP submitted from
# its panel of the import page, imported by Workouts::StravaArchiveImportJob.
# A refused upload returns to that panel.
class StravaArchiveImportsController < ApplicationController
  # The database-counted admission below bounds what is stored; this keeps one
  # account from hammering the endpoint (docs/dev/IMPORT-SOURCES.md).
  rate_limit to: 20, within: 1.hour, only: :create, by: -> { current_user.id }, name: "web-strava-archives",
             with: -> { refuse_rate_limited }

  def create
    @batch = current_user.workout_import_batches.new(
      source: Allure::ImportSources::STRAVA_ARCHIVE.key,
      trigger: "manual",
      sport: Sport.active.find_by(id: archive_params[:strava_sport_id].presence)
    )
    archive = archive_params[:strava_archive]
    validate_archive(archive)
    return refuse if @batch.errors.any?

    @batch.source_bytes = archive.size.to_i
    if (refusal = Workouts::ImportAdmission.new(user: current_user, source: @batch.source,
                                                bytes: @batch.source_bytes).refusal)
      @batch.errors.add(:strava_archive, refusal.message)
      return refuse
    end

    WorkoutImportBatch.transaction do
      @batch.save!
      @batch.source_files.attach(archive)
    end
    Workouts::StravaArchiveImportJob.perform_later(@batch)
    redirect_to workout_import_path(@batch), notice: t("workouts.batch_import.create.success")
  rescue ActiveRecord::RecordInvalid
    refuse
  end

  private

  def archive_params
    params.fetch(:workout_import_batch, {}).permit(:strava_archive, :strava_sport_id)
  end

  def validate_archive(archive)
    if !archive.respond_to?(:original_filename)
      @batch.errors.add(:strava_archive, t("workouts.batch_import.errors.missing_strava_archive"))
    elsif File.extname(archive.original_filename.to_s).downcase != ".zip"
      @batch.errors.add(:strava_archive, t("workouts.batch_import.errors.strava_archive_not_zip"))
    elsif archive.size.to_i > Allure::StravaArchive::MAX_BYTES
      @batch.errors.add(:strava_archive, t("workouts.batch_import.errors.source_too_large",
                                           max: Allure::StravaArchive::MAX_SIZE_LABEL))
    end
  end

  def refuse_rate_limited
    @batch = current_user.workout_import_batches.new(source: Allure::ImportSources::STRAVA_ARCHIVE.key)
    @batch.errors.add(:strava_archive, t("workouts.batch_import.errors.rate_limited"))
    refuse(status: :too_many_requests)
  end

  def refuse(status: :unprocessable_content)
    @sports = Sport.catalog_order
    @manual_form = ManualWorkoutForm.blank(user: current_user)
    @equipments = current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
    @initial_source = Allure::ImportSources::STRAVA_ARCHIVE.key
    render "workout_imports/new", status:
  end
end
