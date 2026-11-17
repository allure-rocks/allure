# frozen_string_literal: true

require "openapi_first"

# Contract tests for the REST API (docs/dev/API.md): a request spec calls
# `expect_api_contract` after a request, and the request and its response are
# validated against docs/openapi/v1.yaml.
module OpenapiContract
  BASE_PATH = "/api/rest/v1"

  def self.definition
    @definition ||= OpenapiFirst.load(Rails.root.join("docs/openapi/v1.yaml").to_s) do |config|
      config.path = ->(rack_request) { rack_request.path.delete_prefix(BASE_PATH) }
    end
  end

  # `request: false` checks the response only, for a request a spec sends
  # broken on purpose.
  def expect_api_contract(request: true)
    rack_request = Rack::Request.new(self.request.env)
    rack_request.body&.rewind
    if request
      validated_request = OpenapiContract.definition.validate_request(rack_request)
      expect(validated_request.error).to be_nil,
                                         "request #{self.request.method} #{self.request.path} breaks the contract: " \
                                         "#{validated_request.error&.message}"
    end

    rack_response = Rack::Response[response.status, response.headers.to_h, [ response.body ]]
    validated_response = OpenapiContract.definition.validate_response(rack_request, rack_response)
    expect(validated_response.error).to be_nil,
                                        "response #{response.status} to #{self.request.method} #{self.request.path} breaks the contract: " \
                                        "#{validated_response.error&.message}"
  end
end

RSpec.configure do |config|
  config.include OpenapiContract, type: :request
end
