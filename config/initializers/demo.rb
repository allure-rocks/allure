# frozen_string_literal: true

# Refuse an unsafe demo configuration before any server or worker starts: the
# operator must not be a shared account, and a configured operator needs its
# stable DEMO_OPERATOR_PASSWORD. #accounts also checks every read, so a seed or
# credential rendering cannot expose the operator if the configuration changes
# after boot.
Rails.application.config.after_initialize do
  next unless Allure::Demo.enabled?

  Allure::Demo.validate!
  if Allure::Demo.operator_username.blank? && Allure::Demo.operator_password.present?
    Rails.logger.warn(
      "[demo] DEMO_OPERATOR_PASSWORD is set without INSTANCE_OPERATOR_USERNAME; the console stays closed"
    )
  end
end
