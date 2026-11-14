# frozen_string_literal: true

class WorkoutFilesController < ApplicationController
  def show
    workout = Workout.find_by_short_id!(params[:workout_id])
    raise ActiveRecord::RecordNotFound unless workout.user == current_user

    unless workout.original_file.attached?
      raise ActiveRecord::RecordNotFound
    end

    response.headers["Cache-Control"] = "private, no-store"
    # The importer always stores the blob with the content type of the format
    # it detected, so the fallback only covers rows written before that.
    fallback = Allure::ImportFormat.for_key(workout.import_format)&.content_type
    send_data workout.original_file.download,
              filename: workout.original_file.filename.to_s,
              type: workout.original_file.content_type || fallback,
              disposition: "attachment"
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
