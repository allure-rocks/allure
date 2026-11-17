# frozen_string_literal: true

# The API reference (docs/dev/API.md, DESIGN.md §20.19). `api` is the Allure
# page; `reference` is the bare Scalar document it embeds in a same-origin
# iframe, which loads the OpenAPI document with the member's session.
class DevelopersController < ApplicationController
  def api
    @api_base_url = "#{Allure::Federation.config.base_url}#{Api::Rest::V1::Document::BASE_PATH}"
  end

  def reference
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    render layout: "api_reference"
  end
end
