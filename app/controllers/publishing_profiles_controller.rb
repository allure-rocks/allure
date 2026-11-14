# frozen_string_literal: true

class PublishingProfilesController < ApplicationController
  before_action :ensure_publishing_profiles, only: :index
  before_action :set_profile, only: %i[show edit update destroy restore_defaults]

  def index
    @profiles = current_user.publishing_profiles.order(:position, :id)
  end

  def show
    @active_publications = @profile.workout_publications.active.count
  end

  def new
    @profile = current_user.publishing_profiles.new(
      audience: "public",
      settings: PublishingProfile::DEFAULT_SETTINGS.deep_dup
    )
  end

  def create
    @profile = current_user.publishing_profiles.new(profile_attributes)
    @profile.position = current_user.publishing_profiles.maximum(:position).to_i + 1

    if @profile.save
      redirect_to publishing_profile_path(@profile), notice: t("publishing_profiles.create.success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @profile.update(profile_attributes)
      redirect_to publishing_profile_path(@profile), notice: t("publishing_profiles.update.success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def restore_defaults
    @profile.update!(
      settings: PublishingProfile::DEFAULT_SETTINGS.deep_dup,
      publish_delay_seconds: PublishingProfile::PUBLISH_DELAYS.fetch("immediate"),
      auto_publish: false,
      auto_publish_exclude_commute: false,
      auto_publish_excluded_sports: []
    )
    redirect_to publishing_profile_path(@profile), notice: t("publishing_profiles.restore_defaults.success")
  end

  def destroy
    if @profile.built_in?
      redirect_to publishing_profiles_path, alert: t("publishing_profiles.destroy.built_in")
    else
      @profile.destroy!
      redirect_to publishing_profiles_path, notice: t("publishing_profiles.destroy.success")
    end
  end

  private

  def ensure_publishing_profiles
    PublishingProfile.ensure_built_ins_for!(current_user)
  end

  def set_profile
    @profile = current_user.publishing_profiles.find(params[:id])
  end

  def profile_attributes
    permitted = params.fetch(:publishing_profile, {}).permit(
      :name,
      :audience,
      :publish_delay_seconds,
      :auto_publish,
      :auto_publish_exclude_commute,
      :auto_publish_acknowledged,
      { auto_publish_excluded_sports: [] },
      settings: [ *PublishingProfile::BOOLEAN_SETTING_KEYS, { metrics: [] } ]
    )
    raw_settings = permitted[:settings].to_h.stringify_keys
    # An unchecked box submits nothing: it is an explicit `false`, which is
    # what closes a setting whose absence means enabled (`comments`).
    settings = PublishingProfile::BOOLEAN_SETTING_KEYS.index_with do |key|
      ActiveModel::Type::Boolean.new.cast(raw_settings[key]) == true
    end
    settings["metrics"] = Array(raw_settings["metrics"]).compact_blank.map(&:to_s)

    attributes = {
      name: permitted[:name],
      audience: permitted[:audience].presence || @profile&.audience || "public",
      settings:
    }
    # The delay is a profile policy, not a snapshot setting; a blank select
    # keeps the stored value instead of nulling the column.
    delay = Integer(permitted[:publish_delay_seconds], exception: false) if permitted[:publish_delay_seconds].present?
    attributes[:publish_delay_seconds] = delay if delay
    # Automatic publishing (PLAN_AUTO_PUBLISHING.md) is a profile policy too;
    # turning it on is refused by the model without the acknowledgement.
    %i[auto_publish auto_publish_exclude_commute auto_publish_acknowledged].each do |key|
      attributes[key] = ActiveModel::Type::Boolean.new.cast(permitted[key]) == true if permitted.key?(key)
    end
    # The form always sends the sport exclusion list (a hidden empty value), so
    # unticking every sport clears it; the model drops the blank entry.
    if permitted.key?(:auto_publish_excluded_sports)
      attributes[:auto_publish_excluded_sports] = permitted[:auto_publish_excluded_sports]
    end
    attributes
  end
end
