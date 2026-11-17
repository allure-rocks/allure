# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The account's equipment (docs/dev/API.md).
      class EquipmentController < BaseController
        require_scope "read"

        def index
          equipment = current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
          render json: { data: equipment.map { CatalogSerializers.equipment(it) } }
        end

        def show
          equipment = current_user.equipments.includes(:equipment_type).find_by_short_id!(params[:id])
          return unless stale?(etag: equipment)

          render json: CatalogSerializers.equipment(equipment)
        end
      end
    end
  end
end
