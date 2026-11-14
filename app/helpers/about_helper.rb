# frozen_string_literal: true

require "uri"

# The About dialog (DESIGN.md §10.23): the instance, the outside services it
# is configured to use, the source of the running code, and the credits.
module AboutHelper
  Service = Data.define(:key, :hosts)

  # Only what this instance has switched on, each with the hosts it reaches,
  # so a member can see where their data may go.
  def about_services
    services = [ Service.new(:maps, about_hosts(Allure::Maps.config.style_url, Allure::Maps.config.dark_style_url,
                                                 Allure::Maps.config.raster_template)) ]
    services << Service.new(:geocoding, about_hosts(Allure::Toponyms::Config.base_url)) if Allure::Toponyms::Config.configured?
    services << Service.new(:elevation, about_hosts(Allure::Elevation::Config.base_url)) if Allure::Elevation::Config.configured?
    if Allure::Weather::Config.enabled?
      services << Service.new(:weather, about_hosts(Allure::Weather::Config.forecast_url, Allure::Weather::Config.archive_url))
    end
    services << Service.new(:push, about_hosts(*Allure::Push::Config.relay_origins)) if Allure::Push::Config.enabled?
    providers = Allure::Auth::Providers.enabled.map(&:label)
    services << Service.new(:identity, providers) if providers.any?
    imports = Allure::RemoteImports::Config.enabled_providers.map { t("about.services.import_names.#{it}") }
    services << Service.new(:imports, imports) if imports.any?
    services << Service.new(:federation, []) if Allure::Federation::Config.enabled?
    services
  end

  def about_operator
    username = User.operator_username
    User.find_by(username:) if username.present?
  end

  private

  def about_hosts(*urls)
    urls.filter_map do |url|
      URI.parse(url.to_s.gsub(/\{[xyz]\}/, "0")).host
    rescue URI::InvalidURIError
      nil
    end.uniq
  end
end
