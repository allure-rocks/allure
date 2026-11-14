# frozen_string_literal: true

# Automated funding providers. `to_prepare` runs at boot and after every code
# reload — the registry constant itself lives under the autoloaded lib/, so a
# reload recreates it and the registration must be renewed with it. The
# registry's own state and the master switch are still evaluated at call time.
Rails.application.config.to_prepare do
  Allure::Funding::Providers.register(Funding::Providers::Stripe)
end
