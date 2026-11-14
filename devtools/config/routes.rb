# frozen_string_literal: true

# Development-only routes (AGENTS.md, "Development tools"). The engine is
# required from config/application.rb only when `Rails.env.local?`, and the
# devtools directory never reaches the production image, so these routes do not
# exist in production.
Rails.application.routes.draw do
  namespace :devtools, module: :dev_tools do
    resource :impersonation, only: %i[show create destroy]
  end
end
