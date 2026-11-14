# frozen_string_literal: true

module ApiTokenHelpers
  # A usable token for `user` and the Authorization header that presents it.
  def api_headers_for(user, scopes: %w[read], **headers)
    _token, secret = ApiToken.issue!(user:, name: "Spec client", scopes:)
    { "Authorization" => "Bearer #{secret}", "Accept" => "application/json" }.merge(headers)
  end
end

RSpec.configure do |config|
  config.include ApiTokenHelpers
end
