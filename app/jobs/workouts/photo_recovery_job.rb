# frozen_string_literal: true

module Workouts
  class PhotoRecoveryJob < ApplicationJob
    queue_as :default

    def perform
      return unless Allure::Photos::Config.enabled?

      WorkoutPhoto.processing.where(updated_at: ...10.minutes.ago).order(:id).limit(200).each do |photo|
        PhotoProcessJob.perform_later(photo) unless photo.user.deactivated?
      end
    end
  end
end
