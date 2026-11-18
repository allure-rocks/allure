# frozen_string_literal: true

module Settings
  # Assistant consent (docs/dev/AI.md): off for every account until it opts in.
  # Withdrawing consent stops every future generation at once and keeps the
  # summaries already written until the owner deletes them here.
  class AssistantController < ApplicationController
    before_action :require_feature

    def show
      @user = current_user
      @stored_count = stored_scope.count
    end

    def update
      @user = current_user
      enabling = ActiveModel::Type::Boolean.new.cast(assistant_params[:ai_enabled])
      if @user.update(assistant_params)
        notice = enabling ? "settings.assistant.update.enabled" : "settings.assistant.update.disabled"
        redirect_to settings_assistant_path, notice: t(notice)
      else
        @stored_count = stored_scope.count
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      count = stored_scope.delete_all
      redirect_to settings_assistant_path, notice: t("settings.assistant.destroy.success", count:)
    end

    private

    def stored_scope = WorkoutSummary.where(workout_id: current_user.workouts.select(:id))

    def assistant_params = params.require(:user).permit(:ai_enabled)

    def require_feature
      raise ActiveRecord::RecordNotFound unless Allure::Assistant::Config.enabled?
    end
  end
end
