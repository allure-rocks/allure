source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

# PostGIS. Tracks are stored as geography(LineString,4326) / geography(Point,4326),
# so the spatial adapter is a hard requirement, not an add-on.
gem "activerecord-postgis-adapter", "~> 11.1"
gem "rgeo", "~> 3.1"
gem "rgeo-geojson", "~> 2.2"
# GPX is parsed through Nokogiri::XML::Reader so point limits can be enforced
# while streaming and parser-specific objects never enter the domain layer.
gem "nokogiri", "~> 1.19"
# ZIP batch imports are read in-process so archive paths are never extracted
# through a shell command.
gem "rubyzip", "~> 3.2"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Second factors (docs/dev/AUTH.md): authenticator codes, their enrolment QR
# code, and passkeys / security keys.
gem "rotp", "~> 6.4"
gem "rqrcode", "~> 3.1"
gem "webauthn", "~> 3.5"

# Identity providers (docs/dev/AUTH.md): the OmniAuth handshake with Rails CSRF
# protection on its request phase, OpenID Connect for Google and a generic
# provider, and Sign in with Apple's form-post flow.
gem "omniauth", "~> 2.4"
gem "omniauth-rails_csrf_protection", "~> 2.0"
gem "omniauth_openid_connect", "~> 0.8"
gem "omniauth-apple", "~> 1.3"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Metrics for Prometheus/Grafana. Yabeda is the collector framework, the
# Prometheus adapter renders the text exposition, and yabeda-rails supplies the
# request count/duration metrics. There is no Solid Queue adapter: queue and
# federation gauges are scrape-time collect blocks (docs/dev/METRICS.md).
gem "yabeda"
gem "yabeda-prometheus"
gem "yabeda-rails"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.2"
# image_processing 2 no longer depends on its backends; libvips is the only one
# in use (avatars, the tile-less route image renderer, Active Storage).
gem "ruby-vips", "~> 2.3"

# Pagination for the local timeline. Pagy is the only pagination choice that
# fits the existing server-rendered Hotwire style without an SPA helper.
gem "pagy"
# GitLab feedback submissions use the API server-side; the token never reaches
# the browser.
gem "httparty"
gem "multipart-post"
# The Model Context Protocol endpoint for AI assistants (docs/dev/MCP.md), served
# stateless from a controller; the official SDK tracks protocol revisions.
gem "mcp", "~> 1.10"
# Push notifications for the iOS companion (docs/dev/PUSH.md): RFC 8291
# payload encryption and the VAPID header; the request itself goes through the
# federation client and its SSRF guard.
gem "web-push", "~> 3.1"

# Frontend build. Tabler ships as npm packages plus SCSS, so Vite replaces the
# asset pipeline entirely — there is deliberately no Propshaft or importmap here.
gem "vite_rails", "~> 3.11"

group :development, :test do
  gem "rspec-rails", "~> 8.1"
  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.8"
  gem "dotenv-rails", "~> 3.2"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  gem "shoulda-matchers", "~> 8.0"
  # Federation is tested offline against pinned fixtures captured from real
  # instances — see spec/fixtures/vcr_cassettes and PLAN.md §6 (Tier 1).
  gem "webmock", "~> 3.26"
  gem "vcr", "~> 6.4"
  # The public REST API's contract tests validate every request and response
  # against docs/openapi/v1.yaml (docs/dev/API.md).
  gem "openapi_first", "~> 4.4"
end
