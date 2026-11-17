# frozen_string_literal: true

module Settings
  # The federation diagnostics and controls moved into the administration
  # console (`/admin/federation`, docs/dev/ADMIN.md). This legacy address only
  # redirects the operator, and still answers 404 to everyone else so it never
  # confirms the console's existence.
  class FederationController < ApplicationController
    before_action :require_operator

    def show
      redirect_to admin_federation_path
    end

    private

    def require_operator
      raise ActiveRecord::RecordNotFound unless instance_operator?
    end
  end
end
