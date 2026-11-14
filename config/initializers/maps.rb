# frozen_string_literal: true

Rails.application.config.after_initialize do
  Allure::Maps.config = Allure::Maps::Config.new

  config = Allure::Maps.config

  if Rails.env.production? && !config.secure?
    raise Allure::Maps::Config::InvalidStyleUrl,
          "MAP_STYLE_URL must use https in production (got #{config.style_url}). " \
          "Browsers block plain-HTTP subresources on an https page, so the basemap would never load."
  end

  if Rails.env.production? && !config.raster_secure?
    raise Allure::Maps::Config::InvalidRasterTemplate,
          "MAP_RASTER_TEMPLATE must use https in production (got #{config.raster_template})."
  end

  Rails.logger.info(
    "[maps] style=#{config.style_url} theme_aware=#{config.theme_aware?}"
  )
end
