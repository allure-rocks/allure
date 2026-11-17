# frozen_string_literal: true

module Admin
  # Instance and environment diagnostics (docs/dev/ADMIN.md). Read-only.
  class SystemController < BaseController
    def show
      @diagnostics = System::Diagnostics.new.call
    end
  end
end
