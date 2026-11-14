# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The account's publishing profiles (PLAN_API.md §6.2), named by their
      # ShortUUID for the publication endpoints.
      class PublishingProfilesController < BaseController
        require_scope "read"

        def index
          profiles = current_user.publishing_profiles.order(:position, :id)
          render json: { data: profiles.map { CatalogSerializers.publishing_profile(it) } }
        end
      end
    end
  end
end
