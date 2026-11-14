# frozen_string_literal: true

module Allure
  # Open-registration gate (M4 Slice 1). Open by default so a fresh instance
  # accepts sign-ups; single-user instances set ALLOW_REGISTRATION=false and
  # the sign-in page says so plainly instead of linking a dead form.
  module Registration
    def self.open?
      default = defined?(Rails) && Rails.env.production? ? "false" : "true"
      ENV.fetch("ALLOW_REGISTRATION", default) == "true"
    end
  end
end
