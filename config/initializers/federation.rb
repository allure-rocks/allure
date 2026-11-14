# frozen_string_literal: true

Rails.application.config.after_initialize do
  Allure::Federation.config = Allure::Federation::Config.new

  config = Allure::Federation.config

  if Rails.env.production?
    unless config.secure?
      raise Allure::Federation::Config::InvalidBaseUrl,
            "FEDERATION_BASE_URL must use https in production (got #{config.base_url}). " \
            "Remote instances will refuse to federate over plain HTTP."
    end

    if config.allow_private_ips?
      raise "ALLOW_PRIVATE_IPS must not be enabled in production: it disables the SSRF guard."
    end
  end

  Rails.logger.info(
    "[federation] identity=#{config.domain} base_url=#{config.base_url} " \
    "private_ips=#{config.allow_private_ips?}"
  )
end
