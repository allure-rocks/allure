# frozen_string_literal: true

module DemoSeed
  # Every seeded account signs in with a local address (docs/dev/DEMO.md). The
  # domain follows the instance the seed runs on — `allure.test` in the default
  # development setup, `demo.allure.rocks` on the public demo — so a manifest
  # never hardcodes a host. `DEMO_EMAIL_DOMAIN` pins another one.
  module Emails
    module_function

    def domain = Allure::Demo.email_domain

    def for(username) = "#{username}@#{domain}"
  end
end
