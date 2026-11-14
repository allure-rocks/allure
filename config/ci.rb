# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Tests: Prepare database", "RAILS_ENV=test bin/rails db:prepare"
  step "Tests: RSpec", "RAILS_ENV=test bundle exec rspec"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
end
