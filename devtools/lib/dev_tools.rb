# frozen_string_literal: true

# Development-only tools (AGENTS.md, "Development tools"). Required from
# config/application.rb when `Rails.env.local?`; the directory is excluded from
# the production image and from the Docker build context, so nothing under this
# namespace exists in production — no route, no helper, no partial, no locale.
module DevTools
end

require_relative "dev_tools/engine"
