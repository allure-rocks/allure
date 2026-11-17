# frozen_string_literal: true

module Api
  module Rest
    module V1
      # `GET /me` and `GET /sports` (docs/dev/API.md): readable with any scope.
      class AccountsController < BaseController
        def me
          render json: CatalogSerializers.me(current_user, Current.api_token)
        end

        def sports
          sports = Sport.where(active: true).order(:position)
          return unless stale?(etag: [ "sports", sports.maximum(:updated_at), I18n.available_locales ])

          render json: { data: sports.map { CatalogSerializers.sport(it) } }
        end
      end
    end
  end
end
