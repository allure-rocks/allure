# frozen_string_literal: true

require "webmock/rspec"
require "vcr"

# Federation is tested offline. Every outbound HTTP call must either be stubbed
# or replayed from a pinned cassette — see PLAN.md §6 (Tier 1). Nothing in the
# suite is allowed to touch the network, so that CI stays deterministic and a
# remote instance changing its output can never turn our build red by surprise.
WebMock.disable_net_connect!(allow_localhost: false)

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/fixtures/vcr_cassettes").to_s
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Record once, then replay forever. Re-recording is a deliberate act:
  #   VCR_RECORD=all bundle exec rspec spec/federation/...
  config.default_cassette_options = {
    record: ENV["VCR_RECORD"]&.to_sym || :none,
    match_requests_on: %i[method uri]
  }

  # Signature headers are time-dependent; never persist them.
  config.filter_sensitive_data("<SIGNATURE>") { |i| i.request.headers["Signature"]&.first }
  config.filter_sensitive_data("<DATE>") { |i| i.request.headers["Date"]&.first }
end
