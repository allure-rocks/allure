# frozen_string_literal: true

module Admin
  # The administration landing page: instance-wide numbers and the most recent
  # accounts, publications, imports, and audited operator actions.
  class DashboardController < BaseController
    def show
      @overview = Dashboard::Overview.new.call
    end
  end
end
