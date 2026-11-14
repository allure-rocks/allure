# frozen_string_literal: true

# Lets the iOS companion use this instance's passkeys (PLAN_AUTH.md §9):
# Associated Domains reads the `webcredentials` apps from here. Absent until
# the operator names the app identifiers.
class AppleAppSiteAssociationsController < ApplicationController
  allow_unauthenticated_access

  def show
    apps = Allure::Auth::Config.ios_app_ids
    return head :not_found if apps.empty?

    render json: { webcredentials: { apps: } }
  end
end
