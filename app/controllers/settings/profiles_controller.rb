# frozen_string_literal: true

module Settings
  # The current user's public identity: display name, biography, and avatar
  # (upload, shuffle the generated art, pick Gravatar, or remove the upload).
  # The self-declared leaderboard category lives here too (docs/dev/SEGMENTS.md
  # §8.7); leaderboard participation itself lives on each segment page.
  class ProfilesController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user
      attributes = profile_params
      upload = attributes.delete(:avatar)
      crop = attributes.delete(:avatar_crop)
      remove_avatar = ActiveModel::Type::Boolean.new.cast(attributes.delete(:remove_avatar))

      @user.assign_attributes(attributes)

      if upload.present?
        Users::AvatarUpload.new(user: @user).call(upload, crop:)
      elsif remove_avatar
        @user.avatar.purge_later if @user.avatar.attached?
      end

      if @user.save
        redirect_to settings_profile_path, notice: t("settings.profile.update.success")
      else
        render :show, status: :unprocessable_content
      end
    rescue Users::AvatarUpload::Invalid => error
      @user.errors.add(:avatar, error.message)
      render :show, status: :unprocessable_content
    end

    # Rotates the generated-avatar seed. Inline endpoint: the settings page
    # swaps the preview with the fragment, so the seed is saved immediately.
    def regenerate_avatar
      @user = current_user
      @user.update!(avatar_seed: SecureRandom.random_number(2**31))

      render partial: "settings/profiles/avatar_preview", locals: { user: @user }
    end

    private

    def profile_params
      keys = %i[display_name bio gravatar_opt_in avatar remove_avatar leaderboard_category
                profile_statistics_audience profile_records_audience discoverable]
      keys.concat(%i[funding_badge_hidden funding_badge_color]) if Allure::Funding.enabled? && !helpers.hotwire_native_app?
      params.require(:user).permit(*keys, avatar_crop: %i[x y size width height])
    end
  end
end
