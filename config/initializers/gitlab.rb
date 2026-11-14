# frozen_string_literal: true

Rails.application.config.after_initialize do
  begin
    Allure::Gitlab.config = Allure::Gitlab::Config.new

    config = Allure::Gitlab.config
    if config.enabled?
      config.validate!
      raise Allure::Gitlab::Config::InvalidConfiguration, "GITLAB_API_URL must use HTTPS in production" if Rails.env.production? && !config.secure?

      Rails.logger.info "[gitlab] feedback integration enabled project=#{config.project_id}" if config.configured?
    end
  rescue Allure::Gitlab::Config::InvalidConfiguration => e
    Rails.logger.warn "[gitlab] feedback integration disabled: #{e.message}"
  end
end
