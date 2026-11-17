# frozen_string_literal: true

# The manual import source (docs/dev/MANUAL-ENTRY.md): a workout typed in from
# the import page's « Saisie manuelle » panel. A refused form returns to that
# panel with what was typed; editing an entry goes through the workout's own
# edit page (WorkoutsController).
class ManualWorkoutsController < ApplicationController
  PERMITTED = [
    *ManualWorkoutForm.attribute_names.map(&:to_sym).excluding(:equipment_ids), { equipment_ids: [] }
  ].freeze

  def create
    @manual_form = ManualWorkoutForm.from_params(manual_params, user: current_user)
    attributes = @manual_form.to_attributes
    if attributes
      result = Workouts::ManualEntry.create(user: current_user, attributes:,
                                            equipment_ids: @manual_form.submitted_equipment_ids)
      return redirect_to workout_path(result.workout), notice: t("workouts.manual.create.success") if result.success?

      @manual_form.adopt_errors(result.workout)
    end

    @batch = current_user.workout_import_batches.new
    @sports = Sport.catalog_order
    @equipments = current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
    @initial_source = Allure::ImportSources::MANUAL.key
    render "workout_imports/new", status: :unprocessable_content
  end

  private

  def manual_params = params.fetch(:manual_workout, {}).permit(*PERMITTED)
end
