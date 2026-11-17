# frozen_string_literal: true

# Sign in with Apple answers with a cross-site form POST (docs/dev/AUTH.md),
# which carries no SameSite=Lax cookie: the session holding the OmniAuth state
# is missing. This page re-posts Apple's fields to the OmniAuth callback from
# this origin, where the browser sends the session cookie again. It reads and
# writes no session itself.
class AppleFormPostsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  FIELDS = %w[code state id_token user error].freeze

  def create
    @fields = params.permit(*FIELDS).to_h.compact_blank
    response.headers["Cache-Control"] = "no-store"
    render layout: false
  end
end
