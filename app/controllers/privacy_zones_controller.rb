# frozen_string_literal: true

class PrivacyZonesController < ApplicationController
  SEARCH_QUERY_LENGTH = 3..200

  before_action :set_privacy_zone, only: %i[edit update destroy]
  rate_limit to: 30, within: 1.minute, only: :search, by: -> { current_user.id },
    name: "privacy-zone-search", with: -> { head :too_many_requests }

  def index
    @privacy_zones = current_user.privacy_zones.order(active: :desc, created_at: :asc, id: :asc)
  end

  def new
    @privacy_zone = current_user.privacy_zones.new(active: true, radius_meters: 100)
  end

  def create
    @privacy_zone = current_user.privacy_zones.new(privacy_zone_params)
    if @privacy_zone.save
      redirect_to privacy_zones_path, notice: t("privacy_zones.create.success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @privacy_zone.update(privacy_zone_params)
      redirect_to privacy_zones_path, notice: t("privacy_zones.update.success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @privacy_zone.destroy!
    redirect_to privacy_zones_path, notice: t("privacy_zones.destroy.success")
  end

  # Forward geocoding for the zone editor (DESIGN.md §14.4). The browser never
  # talks to the provider: the query leaves through the instance's own
  # Nominatim client, is named `privacy_zone_query` so the parameter filter
  # keeps it out of the logs, and is neither cached nor stored.
  def search
    return head :not_found unless Allure::Toponyms::Config.configured?

    query = params[:privacy_zone_query].to_s.squish
    return head :unprocessable_content unless SEARCH_QUERY_LENGTH.cover?(query.length)

    response.headers["Cache-Control"] = "no-store"
    client = Allure::Toponyms::Nominatim.new(base_url: Allure::Toponyms::Config.base_url)
    render json: { results: client.search(query:, language: I18n.locale.to_s) }
  rescue Allure::Toponyms::Nominatim::UnavailableError
    head :service_unavailable
  end

  private

  def set_privacy_zone
    @privacy_zone = current_user.privacy_zones.find(params[:id])
  end

  def privacy_zone_params
    attributes = %i[name latitude longitude radius_meters]
    attributes << :active if action_name == "update"
    params.fetch(:privacy_zone, {}).permit(*attributes)
  end
end
