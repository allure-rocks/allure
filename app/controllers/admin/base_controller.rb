# frozen_string_literal: true

module Admin
  # Operator-only administration console. Non-operators get a 404, never a 403:
  # the console's existence is never confirmed to an ordinary account. The
  # normal chrome never links here except for the configured operator.
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_operator
    # Second-factor step-up (docs/dev/AUTH.md), after the 404 so the console
    # is never revealed to anyone else.
    before_action :require_recent_second_factor

    private

    def require_operator
      raise ActiveRecord::RecordNotFound unless instance_operator?
    end
  end
end
