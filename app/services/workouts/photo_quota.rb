# frozen_string_literal: true

module Workouts
  # All writes that change usage lock the account first, then the workout or
  # photo. Processing rows reserve their original's bytes from intake onward.
  class PhotoQuota
    def initialize(user:)
      @user = user
    end

    def limit = @user.photo_quota_bytes || Allure::Photos::Config.default_quota_bytes
    def used = @user.workout_photos.sum(:bytes_total)
    def fits?(additional) = used + additional <= limit
  end
end
