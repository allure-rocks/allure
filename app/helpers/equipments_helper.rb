# frozen_string_literal: true

module EquipmentsHelper
  def equipment_type_name(equipment_type)
    I18n.t("equipment_types.#{equipment_type.slug}", default: equipment_type.label)
  end
end
