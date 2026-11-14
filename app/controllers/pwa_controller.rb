# frozen_string_literal: true

# Installable identity only (DESIGN.md §23): name, icons, colours, start
# URL. No offline caching strategy — the service worker stays absent until
# an offline capability is defined.
class PwaController < ApplicationController
  allow_unauthenticated_access

  def manifest
    response.headers["Cache-Control"] = "public, max-age=86400"
    render template: "pwa/manifest", formats: :json, content_type: "application/manifest+json"
  end
end
