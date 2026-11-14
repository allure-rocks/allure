# frozen_string_literal: true

module Admin
  # Instance and environment diagnostics (PLAN_ADMIN.md §4.8). Read-only.
  class SystemController < BaseController
    def show
      @diagnostics = System::Diagnostics.new.call
    end
  end
end
